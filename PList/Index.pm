#    PList - software for archiving and formatting emails from mailing lists
#    Copyright (C) 2014  Pali Rohár <pali.rohar@gmail.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package PList::Index;

use strict;
use warnings;

use PList::Email::Binary;
use PList::Email::View;

use PList::List::Binary;

use File::Path qw(make_path);
use DBI;
use Cwd;

require DBD::SQLite;
require DBD::mysql;

# directory structure:
#
# [0-9]{5}.list
# deleted
# config

# SQL tables:
#
# emails:
# id, messageid, date, subjectid(subjects), subject, treeid, list, offset, implicit, hasreply, spam
#
# trees:
# id, emailid(emails), date, count
# NOTE: emailid is root of tree, date is smallest non zero and non NULL date from emails for tree, count is number of emails in tree
#
# replies:
# id, emailid1(emails), emailid2(emails), type
# NOTE: type is: 0 - in-reply-to, 1 - references
#
# subjects:
# id, subject (normalized)
# NOTE: subject is normalized (stripped whitespaces, removed leading RE, FWD)
#
# address:
# id, email, name
#
# addressess:
# id, emailid(emails), addressid(address), type
# NOTE: type is: 0 - from, 1 - to, 2 - cc

sub new($$) {

	my ($class, $dir) = @_;

	my $fh;
	if ( not open($fh, "<", $dir . "/config") ) {
		warn "Cannot open config file\n";
		return undef;
	}

	my $config = {};

	while (<$fh>) {
		next if $_ =~ /^\s*#/;
		next unless $_ =~ /^\s*([^=]+)=(.*)$/;
		$config->{$1} = $2;
	}

	$config->{params} = "" unless defined $config->{params};
	$config->{listsize} = 100 * 1024 * 1024 unless $config->{listsize}; # 100MB

	close($fh);

	if ( not defined $config->{driver} ) {
		warn "Driver was not specified in config file\n";
		return undef;
	}

	my $dbh = db_connect($dir, $config->{driver}, $config->{params}, $config->{username}, $config->{password});
	if ( not $dbh ) {
		return undef;
	}

	my $templatedir = $config->{templatedir};
	if ( $templatedir and -e $templatedir ) {
		$ENV{PLIST_TEMPLATE_DIR} = $templatedir;
	}

	my $priv = {
		dir => $dir,
		dbh => $dbh,
		config => $config,
	};

	bless $priv, $class;

}

sub config($$$) {

	my ($priv, $key, $value) = @_;

	my $config = $priv->{config};

	$config->{$key} = $value;

	my $fh;
	if ( not open($fh, ">", $priv->{dir} . "/config") ) {
		warn "Cannot open config file\n";
		return 0;
	}

	foreach ( sort keys %{$config} ) {
		print $fh $_ . "=" . $config->{$_} . "\n" if defined $config->{$_};
	}
	close($fh);

	if ( $key eq "driver" or $key eq "params" or $key eq "username" or $key eq "password" ) {
		$priv->{dbh}->disconnect();
		$priv->{dbh} = db_connect($priv->{dir}, $config->{driver}, $config->{params}, $config->{username}, $config->{password});
		if ( not $priv->{dbh} ) {
			warn "Cannot connect to database\n";
			return 0;
		}
	}

	return 1;

}

sub info($$) {

	my ($priv, $key) = @_;

	if ( $key eq "emailcount" or $key eq "treecount" ) {

		my $dbh = $priv->{dbh};
		my $statement = "SELECT COUNT(*) FROM ";
		my $ret;

		if ( $key eq "emailcount" ) {
			$statement .= "emails";
		} else {
			$statement .= "trees";
		}

		eval {
			my $sth = $dbh->prepare_cached($statement);
			$sth->execute();
			$ret = $sth->fetchall_arrayref();
		} or do {
			return "(unknown)";
		};

		if ( not $ret or not @{$ret} or not ${$ret}[0] ) {
			return "(unknown)";
		}

		return ${${$ret}[0]}[0];

	}

	if ( $key eq "emaillast" ) {
		my $emails = $priv->db_emails(limit => 1, implicit => 0, spam => 0, desc => 1);
		return undef unless @{$emails};
		return $emails->[0];
	}

	return $priv->{config}->{$key};

}

sub DESTROY($) {

	my ($priv) = @_;

	my $dbh = $priv->{dbh};
	$dbh->disconnect();

}

sub db_connect($$$$$) {

	my ($dir, $driver, $params, $username, $password) = @_;

	my $dbh;

	my $cwd = cwd();
	chdir($dir);

	eval {
		$dbh = DBI->connect("DBI:$driver:$params", $username, $password, { RaiseError => 1, AutoCommit => 0 });
	} or do {
		warn $@;
		chdir($cwd);
		return undef;
	};

	chdir($cwd);

	if ( not $dbh ) {
		return undef;
	}

	if ( $driver eq "SQLite" ) {
		$dbh->{sqlite_unicode} = 1; # By default utf8 is turned off
		$dbh->{AutoCommit} = 1; # NOTE: transactions must be disabled when changing pragmas, otherwise foreign_keys will not be changed
		$dbh->do("PRAGMA synchronous = OFF;"); # This will dramatically speed up SQLite inserts (60-120 times) at cost of possible corruption if kernel crash
		$dbh->do("PRAGMA foreign_keys = ON;"); # By default foreign keys constraints are turned off
		$dbh->{AutoCommit} = 0;
	} elsif ( $driver eq "mysql" ) {
		$dbh->{mysql_enable_utf8} = 1; # by default utf8 is turned off
		$dbh->do("SET storage_engine = INNODB;"); # Use InnoDB engine which support transactions
	}

	return $dbh;

}

sub create_tables($$) {

	my ($dbh, $driver) = @_;

	my $statement;

	# NOTE: Higher values are not possible for MySQL INNODB engine
	my $text = "TEXT";
	$text = "VARCHAR(8192) CHARACTER SET utf8" if $driver eq "mysql";

	my $halftext = "TEXT";
	$halftext = "VARCHAR(4096) CHARACTER SET utf8" if $driver eq "mysql";

	my $uniquesize = "";
	$uniquesize = "(255)" if $driver eq "mysql";

	my $uniquehalfsize = "";
	$uniquehalfsize = "(127)" if $driver eq "mysql";

	# NOTE: AUTOINCREMENT is not needed for SQLite PRIMARY KEY
	my $autoincrement = "";
	$autoincrement = "AUTO_INCREMENT" if $driver eq "mysql";

	# NOTE: Equivalents for MySQL are in INSERT/UPDATE SQL statements
	my $ignoreconflict = "";
	$ignoreconflict = "ON CONFLICT IGNORE" if $driver eq "SQLite";

	# NOTE: MySQL does not support transaction for CREATE TABLE, so rollback will not work

	$statement = qq(
		CREATE TABLE subjects (
			id		INTEGER PRIMARY KEY NOT NULL $autoincrement,
			subject		$text,
			UNIQUE (subject $uniquesize) $ignoreconflict
		);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE TABLE emails (
			id		INTEGER PRIMARY KEY NOT NULL $autoincrement,
			messageid	$text NOT NULL,
			date		INTEGER,
			subjectid	INTEGER NOT NULL REFERENCES subjects(id) ON UPDATE CASCADE ON DELETE RESTRICT,
			subject		$text,
			treeid		INTEGER,
			list		$halftext,
			offset		INTEGER,
			implicit	INTEGER NOT NULL,
			hasreply	INTEGER,
			spam		INTEGER,
			UNIQUE (messageid $uniquesize) $ignoreconflict
		);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailsdate ON emails(date);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailssubjectid ON emails(subjectid);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailstreeid ON emails(treeid);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailsimplicitdate ON emails(implicit, date);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailsimplicitspamdate ON emails(implicit, spam, date);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailsimplicittreeid ON emails(implicit, treeid);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailsimplicitsubjectiddate ON emails(implicit, subjectid, date);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailsimplicitsubjectdate ON emails(implicit, subject, date);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailstreeiddate ON emails(treeid, date);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailshasreply ON emails(hasreply);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE TABLE trees (
			id		INTEGER PRIMARY KEY NOT NULL $autoincrement,
			emailid		INTEGER NOT NULL REFERENCES emails(id) ON UPDATE CASCADE ON DELETE RESTRICT,
			date		INTEGER,
			count		INTEGER,
			UNIQUE (emailid) $ignoreconflict
		);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX treesdate ON trees(date);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE TABLE replies (
			id		INTEGER PRIMARY KEY NOT NULL $autoincrement,
			emailid1	INTEGER NOT NULL REFERENCES emails(id) ON UPDATE CASCADE ON DELETE CASCADE,
			emailid2	INTEGER NOT NULL REFERENCES emails(id) ON UPDATE CASCADE ON DELETE RESTRICT,
			type		INTEGER NOT NULL,
			UNIQUE (emailid1, emailid2, type) $ignoreconflict
		);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX repliesemailid1 ON replies(emailid1);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX repliesemailid2 ON replies(emailid2);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE TABLE address (
			id		INTEGER PRIMARY KEY NOT NULL $autoincrement,
			email		$text,
			name		$text,
			UNIQUE (email $uniquehalfsize, name $uniquehalfsize) $ignoreconflict
		);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE TABLE addressess (
			id		INTEGER PRIMARY KEY NOT NULL $autoincrement,
			emailid		INTEGER NOT NULL REFERENCES emails(id) ON UPDATE CASCADE ON DELETE CASCADE,
			addressid	INTEGER NOT NULL REFERENCES address(id) ON UPDATE CASCADE ON DELETE RESTRICT,
			type		INTEGER NOT NULL,
			UNIQUE (emailid, addressid, type) $ignoreconflict
		);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX addressessemailid ON addressess(emailid);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX addressessaddressid ON addressess(addressid);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	# NULL subject for implicit emails
	$statement = qq(
		INSERT INTO subjects (id, subject)
			VALUES (1, NULL)
		;
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	# empty subject for emails without subject
	$statement = qq(
		INSERT INTO subjects (id, subject)
			VALUES (2, "")
		;
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	# NULL address for emails without from header
	$statement = qq(
		INSERT INTO address (id, email, name)
			VALUES (1, NULL, NULL)
		;
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; return 0; };

	return 1;

}

sub create($;$$$$%) {

	my ($dir, $driver, $params, $username, $password, %config) = @_;

	if ( not $driver ) {
		$driver = "SQLite";
	}

	if ( $driver eq "SQLite" and not $params ) {
		$params = "sqlite.db";
	}

	if ( not defined $params ) {
		$params = "";
	}

	if ( not make_path($dir) ) {
		warn "Cannot create dir $dir\n";
		return 0;
	}

	my $fh;
	if ( not open($fh, ">", $dir . "/config") ) {
		warn "Cannot create config file\n";
		rmdir($dir);
		return 0;
	}

	my $dbh = db_connect($dir, $driver, $params, $username, $password);
	if ( not $dbh ) {
		close($fh);
		unlink($dir . "/config");
		rmdir($dir);
		return 0;
	}

	my $ret = create_tables($dbh, $driver);

	$dbh->disconnect();

	if ( not $ret ) {
		close($fh);
		unlink($dir . "/config");
		rmdir($dir);
		return 0;
	}

	$config{driver} = $driver;
	$config{params} = $params;
	$config{username} = $username;
	$config{password} = $password;

	foreach ( sort keys %config ) {
		print $fh $_ . "=" . $config{$_} . "\n" if defined $config{$_};
	}

	close($fh);

	return 1;

}

sub pregen_one_email($$;$) {

	my ($priv, $id, $pemail) = @_;

	my %config = (cgi_templates => 1, nopregen => 1, pemail => $pemail);
	my $str = $priv->view($id, %config);
	return 0 unless $str;

	my $dir = $priv->{dir} . "/pregen";
	unless ( -d $dir ) {
		mkdir $dir or return 0;
	}

	my $subdir = substr($id, 0, 2);
	unless ( -d "$dir/$subdir" ) {
		mkdir "$dir/$subdir" or return 0;
	}

	my $file;
	open($file, ">", "$dir/$subdir/$id.html") or return 0;

	binmode($file, ":raw");

	no warnings "utf8";
	print $file ${$str};
	close($file);

	return 1;

}

sub pregen_all_emails($) {

	my ($priv) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $ret;

	$statement = qq(
		SELECT messageid
			FROM emails
			WHERE implicit = 0 AND spam = 0
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute();
		$ret = $sth->fetchall_arrayref();
	} or do {
		return undef;
	};

	return (0, 0) unless $ret and $ret->[0];

	my $count = 0;
	my $total = 0;

	foreach ( @{$ret} ) {
		if ( $priv->pregen_one_email($_->[0]) ) {
			++$count;
		}
		++$total;
	}

	return ($count, $total);

}

sub regenerate($) {

	my ($priv) = @_;

	# TODO

	# drop tables
	# create tables
	# rename listfiles
	# insert emails (ignore removed)
	# remove old listfiles

}

# Remove all leading strings RE: FW: FWD: and mailing list name in square brackets
# After this normalization subject can be used for finding reply emails if in-reply-to header is missing
sub normalize_subject($) {

	my ($subject) = @_;

	return "" unless defined $subject;
	$subject =~ s/^\s*(?:(?:(Re|Fw|Fwd):\s*)*)(?:(\[[^\]]+\]\s*(?:(Re|Fw|Fwd):\s*)+)*)//i;

	return $subject;

}

sub add_one_email($$$$) {

	my ($priv, $pemail, $list, $listfile) = @_;

	my $dbh = $priv->{dbh};
	my $driver = $priv->{config}->{driver};

	my $id = $pemail->id();
	my $rid;

	my $statement;
	my $ret;

	$statement = qq(
		SELECT id, messageid, implicit
			FROM emails
			WHERE messageid = ?
			LIMIT 1
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_hashref("messageid");
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	if ( $ret and $ret->{$id} and not $ret->{$id}->{implicit} ) {
		$@ = "Email already in database";
		return 0;
	}

	if ( $ret and $ret->{$id} ) {
		$rid = $ret->{$id}->{id};
	}

	my $header = $pemail->header("0");

	if ( not $header ) {
		$@ = "Corrupted email";
		return 0;
	}

	my $offset = $list->append($pemail);
	if ( not defined $offset ) {
		eval { $dbh->rollback(); };
		$@ = "Cannot append email to listfile '$listfile'";
		return 0;
	};

	my $from = $header->{from};
	my $to = $header->{to};
	my $cc = $header->{cc};
	my $reply = $header->{reply};
	my $references = $header->{references};
	my $date = $header->{date};
	my $subject = $header->{subject};
	my $nsubject = normalize_subject($subject);

	# NOTE: SQLite has conflict action directly in CREATE TABLE
	my $ignoreconflict = "";
	$ignoreconflict = "ON DUPLICATE KEY UPDATE id=id" if $driver eq "mysql";

	$statement = qq(
		INSERT INTO subjects (subject)
			VALUES (?)
			$ignoreconflict
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($nsubject);
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	my $hasreply = 0;
	$hasreply = 1 if $reply and @{$reply};

	# Insert new email to database (or update implicit email)
	if ( defined $rid ) {
		$statement = qq(
			UPDATE emails
				SET
					date = ?,
					subjectid = (SELECT id FROM subjects WHERE subject = ?),
					subject = ?,
					list = ?,
					offset = ?,
					implicit = 0,
					spam = 0,
					hasreply = ?
				WHERE messageid = ?
			;
		);
	} else {
		$statement = qq(
			INSERT INTO emails (date, subjectid, subject, list, offset, implicit, spam, hasreply, messageid)
				VALUES (
					?,
					(SELECT id FROM subjects WHERE subject = ?),
					?,
					?,
					?,
					0,
					0,
					?,
					?
				)
			;
		);
	}

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($date, $nsubject, $subject, $listfile, $offset, $hasreply, $id);
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	$statement = "SELECT (SELECT MAX(treeid) FROM emails) + 1;";

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute();
		$ret = $sth->fetchall_arrayref();
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	if ( not $ret or not @{$ret} or not ${$ret}[0] ) {
		eval { $dbh->rollback(); };
		return 0;
	}

	my $newtreeid = ${${$ret}[0]}[0];
	$newtreeid = 1 unless defined $newtreeid;

	my @replies;

	if ( $reply and @{$reply} ) {
		push(@replies, [$id, $_, 0]) foreach ( @{$reply} );
	}
	if ( $references and @{$references} ) {
		push(@replies, [$id, $_, 1]) foreach ( @{$references} );
	}

	# Insert in-reply-to and references emails to database as implicit (if not exists)
	$statement = qq(
		INSERT INTO emails (messageid, subjectid, treeid, implicit)
			VALUES (?, 1, ?, 1)
			$ignoreconflict
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(${$_}[1], $newtreeid) foreach (@replies);
		1;
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	# Insert in-reply-to and references edges to database
	$statement = qq(
		INSERT INTO replies (emailid1, emailid2, type)
			VALUES (
				(SELECT id FROM emails WHERE messageid = ?),
				(SELECT id FROM emails WHERE messageid = ?),
				?
			)
			$ignoreconflict
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(@{$_}) foreach (@replies);
		1;
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	my @addressess;

	if ( $from and @{$from} ) {
		foreach ( @{$from} ) {
			$_ =~ /^(\S*) (.*)$/;
			$1 = "" unless defined $1;
			$2 = "" unless defined $2;
			push(@addressess, [$id, $1, $2, 0]);
		}
	}

	if ( $to and @{$to} ) {
		foreach ( @{$to} ) {
			$_ =~ /^(\S*) (.*)$/;
			$1 = "" unless defined $1;
			$2 = "" unless defined $2;
			push(@addressess, [$id, $1, $2, 1]);
		}
	}

	if ( $cc and @{$cc} ) {
		foreach ( @{$cc} ) {
			$_ =~ /^(\S*) (.*)$/;
			$1 = "" unless defined $1;
			$2 = "" unless defined $2;
			push(@addressess, [$id, $1, $2, 2]);
		}
	}

	# Insert pairs email address and name (if not exists)
	$statement = qq(
		INSERT INTO address (email, name)
			VALUES (?, ?)
			$ignoreconflict
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(${$_}[1], ${$_}[2]) foreach (@addressess);
		1;
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	# Insert from, to and cc headers to database for new email
	$statement = qq(
		INSERT INTO addressess (emailid, addressid, type)
			VALUES (
				(SELECT id FROM emails WHERE messageid = ?),
				(SELECT id FROM address WHERE email = ? AND name = ?),
				?
			)
			$ignoreconflict
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(@{$_}) foreach (@addressess);
		1;
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	if ( not $from or not @{$from} ) {
		$statement = qq(
			INSERT INTO addressess (emailid, addressid, type)
				VALUES (
					(SELECT id FROM emails WHERE messageid = ?),
					1,
					0
				)
				$ignoreconflict
			;
		);

		eval {
			my $sth = $dbh->prepare_cached($statement);
			$sth->execute($id);
		} or do {
			eval { $dbh->rollback(); };
			return 0;
		};
	}

	my ($up_reply, $up_references) = $priv->db_replies($id, 1); # emails up
	my ($down_reply, $down_references) = $priv->db_replies($id, 0); # emails down

	my %mergeids;
	foreach (@{$up_reply}, @{$up_references}, @{$down_reply}, @{$down_references}) {
		my $treeid = ${$_}[3];
		next unless defined $treeid;
		$mergeids{$treeid} = 1;
	}

	my $treeid;
	my @mergeids = sort keys %mergeids;
	if ( @mergeids ) {
		$treeid = shift @mergeids;
	} else {
		$treeid = $newtreeid;
	}

	$statement = qq(
		UPDATE emails
			SET treeid = ?
			WHERE messageid = ?
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($treeid, $id);
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	if ( @mergeids ) {
		$statement = qq(
			UPDATE emails
				SET treeid = ?
				WHERE treeid = ?
			;
		);

		eval {
			my $sth = $dbh->prepare_cached($statement);
			$sth->execute($treeid, $_) foreach (@mergeids);
			1;
		} or do {
			eval { $dbh->rollback(); };
			return 0;
		};

		$statement = qq(
			DELETE
				FROM trees
				WHERE id = ?
			;
		);

		eval {
			my $sth = $dbh->prepare_cached($statement);
			$sth->execute($_) foreach (@mergeids);
			1;
		} or do {
			eval { $dbh->rollback(); };
			return 0;
		};
	}

	if ( $treeid != $newtreeid ) {
		$statement = qq(
			UPDATE trees
				SET
					emailid = (SELECT MIN(id) FROM emails WHERE treeid = ? AND date = (SELECT MIN(date) FROM emails WHERE implicit = 0 AND treeid = ?)),
					date = (SELECT MIN(date) FROM emails WHERE implicit = 0 AND treeid = ?),
					count = (SELECT COUNT(*) FROM emails WHERE treeid = ?)
				WHERE
					id = ?
			;
		);
		eval {
			my $sth = $dbh->prepare_cached($statement);
			$sth->execute($treeid, $treeid, $treeid, $treeid, $treeid);
		} or do {
			eval { $dbh->rollback(); };
			return 0;
		};
	} else {
		$statement = qq(
			INSERT INTO trees (id, emailid, date, count)
				VALUES (
					?,
					(SELECT id FROM emails WHERE messageid = ?),
					?,
					1
				)
				$ignoreconflict
			;
		);
		eval {
			my $sth = $dbh->prepare_cached($statement);
			$sth->execute($treeid, $id, $date);
		} or do {
			eval { $dbh->rollback(); };
			return 0;
		};
	}

	eval {
		$dbh->commit();
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	if ( $priv->{config}->{autopregen} ) {
		$priv->pregen_one_email($id, $pemail);
	}

	return 1;

}

sub reopen_listfile($;$$) {

	my ($priv, $list, $listfile) = @_;

	if ( $list and $listfile and ( not -f $priv->{dir} . "/" . $listfile or -s $priv->{dir} . "/" . $listfile < $priv->{config}->{listsize} ) ) {
		return ($list, $listfile);
	}

	if ( not $listfile ) {

		my $dh;
		my @files;

		opendir($dh, $priv->{dir});
		@files = sort grep(/^[0-9]+\.list$/ && -f $_, readdir($dh));
		closedir($dh);

		if ( not @files ) {
			$listfile = "00000.list";
		} else {
			$listfile = $files[-1];
		}

	}

	if ( -f $priv->{dir} . "/" . $listfile and -s $priv->{dir} . "/" . $listfile >= $priv->{config}->{listsize} ) {
		$listfile =~ s/\.list$//;
		$listfile = sprintf("%.5d.list", $listfile+1);
	}

	$list = PList::List::Binary->new($priv->{dir} . "/" . $listfile, 1);
	if ( not $list ) {
		$@ = "Cannot open listfile '$listfile'";
		return undef;
	}

	return ($list, $listfile);

}

sub add_email($$;$) {

	my ($priv, $pemail, $ignorewarn) = @_;

	my ($list, $listfile) = $priv->reopen_listfile();
	if ( not $list or not $listfile ) {
		my $err = $@;
		warn "Cannot add email: $err\n" unless $ignorewarn;
		return 0;
	}

	my $ret = $priv->add_one_email($pemail, $list, $listfile);
	if ( not $ret ) {
		my $err = $@;
		warn "Cannot add email: $err\n" unless $ignorewarn;
		return 0;
	}

	return 1;

}

sub add_list($$;$) {

	my ($priv, $list, $ignorewarn) = @_;

	my $count = 0;
	my $total = 0;

	my $list2;
	my $listfile;

	while ( not $list->eof() ) {
		++$total;
		my $pemail = $list->readnext();
		if ( not $pemail ) {
			warn "Cannot read email\n" unless $ignorewarn;
			next;
		}
		($list2, $listfile) = $priv->reopen_listfile($list2, $listfile);
		if ( not $list2 or not $listfile ) {
			my $err = $@;
			warn "Cannot add email with id '" . $pemail->id() . "': $err\n" unless $ignorewarn;
			next;
		}
		if ( not $priv->add_one_email($pemail, $list2, $listfile) ) {
			my $err = $@;
			warn "Cannot add email with id '" . $pemail->id() . "': $err\n" unless $ignorewarn;
			next;
		}
		++$count;
	}

	return ($count, $total);

}

sub db_stat($;$$) {

	my ($priv, $date1, $date2) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $ret;

	return undef if defined $date1 xor defined $date2;

	if ( not defined $date1 ) {

		$statement = qq(
			SELECT MIN(date), MAX(date)
				FROM emails
				WHERE
					date IS NOT NULL AND
					implicit = 0 AND
					spam = 0
			;
		);

		eval {
			my $sth = $dbh->prepare_cached($statement);
			$sth->execute();
			$ret = $sth->fetchall_arrayref();
		} or do {
			return undef;
		};

		return undef unless $ret and $ret->[0];
		return @{$ret->[0]};

	} else {

		$statement = qq(
			SELECT COUNT(*)
				FROM emails
				WHERE
					date IS NOT NULL AND
					date >= ? AND
					date < ? AND
					implicit = 0 AND
					spam = 0
		);

		eval {
			my $sth = $dbh->prepare_cached($statement);
			$sth->execute($date1, $date2);
			$ret = $sth->fetchall_arrayref();
		} or do {
			return undef;
		};

		return undef unless $ret and $ret->[0];
		return $ret->[0]->[0];

	}

}

sub db_emails($;%) {

	my ($priv, %args) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my @args;
	my $ret;

	if ( exists $args{type} ) {
		if ( $args{type} eq "from" ) {
			$args{type} = 0;
		} elsif ( $args{type} eq "to" ) {
			$args{type} = 1;
		} elsif ( $args{type} eq "cc" ) {
			$args{type} = 2;
		} else {
			delete $args{type};
		}
	}

	# Select all email messageids which match conditions
	$statement = "SELECT * FROM (";
	$statement .= " SELECT e.id AS id, e.messageid AS messageid, e.date AS date, e.subject AS subject, e.treeid AS treeid, af.email AS email, af.name AS name, e.list AS list, e.offset AS offset, e.implicit AS implicit, e.hasreply AS hasreply, e.spam AS spam FROM (";
	$statement .= " SELECT ee.id AS id, ee.messageid AS messageid, ee.date AS date, ee.subject AS subject, ee.treeid AS treeid, ee.list AS list, ee.offset AS offset, ee.implicit AS implicit, ee.hasreply AS hasreply, ee.spam AS spam FROM emails AS ee";

	if ( exists $args{email} or exists $args{name} ) {
		$statement .= " JOIN addressess AS ss ON ss.emailid = ee.id JOIN address AS a ON a.id = ss.addressid";
	}

	$statement .= " WHERE";

	if ( exists $args{id} ) {
		$statement .= " ee.id = ? AND";
		push(@args, $args{id});
	}

	if ( exists $args{messageid} ) {
		$statement .= " ee.messageid = ? AND";
		push(@args, $args{messageid});
	}

	if ( exists $args{treeid} ) {
		$statement .= " ee.treeid = ? AND";
		push(@args, $args{treeid});
	}

	if ( exists $args{date1} ) {
		$statement .= " ee.date >= ? AND";
		push(@args, $args{date1});
	}

	if ( exists $args{date2} ) {
		$statement .= " ee.date < ? AND";
		push(@args, $args{date2});
	}

	if ( exists $args{implicit} ) {
		$statement .= " ee.implicit = ? AND";
		push(@args, $args{implicit});
	}

	if ( exists $args{spam} ) {
		$statement .= " ee.spam = ? AND";
		push(@args, $args{spam});
	}

	if ( exists $args{subject} ) {
		$statement .= " ee.subject LIKE ? AND";
		push(@args, "%" . $args{subject} . "%");
	}

	if ( exists $args{email} ) {
		$statement .= " a.email LIKE ? AND";
		push(@args, "%" . $args{email} . "%");
	}

	if ( exists $args{name} ) {
		$statement .= " a.name LIKE ? AND";
		push(@args, "%" . $args{name} . "%");
	}

	if ( ( exists $args{email} or exists $args{name} ) and exists $args{type} ) {
		$statement .= " ss.type = ? AND";
		push(@args, $args{type});
	}

	$statement =~ s/ WHERE$//;
	$statement =~ s/AND$//;

	$statement .= "ORDER BY ee.date";

	if ( $args{desc} ) {
		$statement .= " DESC";
	}

	if ( exists $args{limit} ) {
		$statement .= " LIMIT ?";
		push(@args, $args{limit});
	}

	# NOTE: OFFSET can be specified only if LIMIT was specified
	if ( exists $args{limit} and exists $args{offset} ) {
		$statement .= " OFFSET ?";
		push(@args, $args{offset});
	}

	$statement .= " ) AS e";
	$statement .= " LEFT OUTER JOIN addressess AS ssf ON ssf.emailid = e.id LEFT OUTER JOIN address AS af ON af.id = ssf.addressid";
	$statement .= " WHERE ssf.type = 0 OR ssf.type IS NULL";
	$statement .= " ) AS eee";
	$statement .= " GROUP BY eee.id";
	$statement .= " ORDER BY eee.date";

	if ( $args{desc} ) {
		$statement .= " DESC";
	}

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(@args);
		$ret = $sth->fetchall_arrayref({});
	} or do {
		return undef;
	};

	return $ret;

}

sub db_emails_str($$;%) {

	my ($priv, $str, %args) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my @args;
	my $ret;

	# Select all email messageids which match conditions
	$statement = "SELECT * FROM (";
	$statement .= " SELECT e.id AS id, e.messageid AS messageid, e.date AS date, e.subject AS subject, e.treeid AS treeid, af.email AS email, af.name AS name, e.list AS list, e.offset AS offset, e.implicit AS implicit, e.hasreply AS hasreply, e.spam AS spam FROM emails AS e";
	$statement .= " LEFT OUTER JOIN addressess AS ssf ON ssf.emailid = e.id LEFT OUTER JOIN address AS af ON af.id = ssf.addressid";
	$statement .= " JOIN addressess AS ss ON ss.emailid = e.id JOIN address AS a ON a.id = ss.addressid";
	$statement .= " WHERE ( e.subject LIKE ? OR a.email LIKE ? OR a.name LIKE ? ) AND";

	push(@args, "%$str%");
	push(@args, "%$str%");
	push(@args, "%$str%");

	if ( exists $args{date1} ) {
		$statement .= " e.date >= ? AND";
		push(@args, $args{date1});
	}

	if ( exists $args{date2} ) {
		$statement .= " e.date < ? AND";
		push(@args, $args{date2});
	}

	if ( exists $args{implicit} ) {
		$statement .= " e.implicit = ? AND";
		push(@args, $args{implicit});
	}

	if ( exists $args{spam} ) {
		$statement .= " e.spam = ? AND";
		push(@args, $args{spam});
	}

	$statement .= " (ssf.type = 0 OR ssf.type IS NULL)";
	$statement .= " ) AS ee";
	$statement .= " GROUP BY ee.id";
	$statement .= " ORDER BY ee.date";

	if ( $args{desc} ) {
		$statement .= " DESC";
	}

	if ( exists $args{limit} ) {
		$statement .= " LIMIT ?";
		push(@args, $args{limit});
	}

	# NOTE: OFFSET can be specified only if LIMIT was specified
	if ( exists $args{limit} and exists $args{offset} ) {
		$statement .= " OFFSET ?";
		push(@args, $args{offset});
	}

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(@args);
		$ret = $sth->fetchall_arrayref({});
	} or do {
		return undef;
	};

	return $ret;

}

sub db_treeid($$$) {

	my ($priv, $id, $rid) = @_;

	my $dbh = $priv->{dbh};

	my $where = "messageid";
	$where = "id" if $rid;

	my $statement;
	my $ret;

	$statement = qq(
		SELECT treeid
			FROM emails
			WHERE $where = ?
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref();
	} or do {
		return undef;
	};

	return undef unless $ret and $ret->[0];
	return $ret->[0]->[0];

}

sub db_graph($$;$) {

	my ($priv, $treeid, $withspam) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $ret;

	if ( not $withspam ) {
		$withspam = "AND e1.spam = 0";
	} else {
		$withspam = "";
	}

	$statement = qq(
		SELECT r.emailid2 AS id1, r.emailid1 AS id2, r.type AS type
			FROM emails AS e1
			JOIN replies AS r ON r.emailid2 = e1.id
			WHERE e1.treeid = ?
			$withspam
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($treeid);
		$ret = $sth->fetchall_arrayref({});
	} or do {
		return undef;
	};

	return $ret;

}

sub djs_makeset($$$) {

	my ($parent, $size, $i) = @_;

	$parent->{$i} = $i;
	$size->{$i} = 1;

}

sub djs_merge($$$$) {

	my ($parent, $size, $a, $b) = @_;

	if ( $size->{$a} < $size->{$b} ) {
		($a, $b) = ($b, $a);
	}

	$parent->{$b} = $a;
	$size->{$a} += $size->{$b};

}

sub djs_find($$$) {

	my ($parent, $size, $i) = @_;

	my $root = $i;

	while ( $root != $parent->{$root} ) {
		$root = $parent->{$root};
	}

	while ( $i != $parent->{$i} ) {
		my $par = $parent->{$i};
		$parent->{$i} = $root;
		$i = $par;
	}

	return $root;

}

sub db_tree($$;$$$$) {

	# TODO: implement $limitup and $limitdown

	my ($priv, $id, $desc, $rid, $limitup, $limitdown) = @_;

	my $treeid;

	if ( defined $rid and $rid == 2 ) {
		$treeid = $id;
	} else {
		$treeid = $priv->db_treeid($id, $rid);
		return undef unless defined $treeid;
	}

	my $emails = $priv->db_emails(treeid => $treeid, desc => $desc, spam => 0);
	return undef unless $emails and @{$emails};

	my $graph = $priv->db_graph($treeid, $desc);
	return undef unless $graph;

	my %emails;
	$emails{$_->{id}} = $_ foreach @{$emails};

	# in-reply-to
	my %graph0;
	my %graphr0;

	$graph0{$_} = [] foreach keys %emails;
	$graphr0{$_} = [] foreach keys %emails;

	# references
	my %graph1;
	my %graphr1;

	$graph1{$_} = [] foreach keys %emails;
	$graphr1{$_} = [] foreach keys %emails;

	foreach ( @{$graph} ) {
		my $id1 = $_->{id1};
		my $id2 = $_->{id2};
		my $type = $_->{type};
		if ( $type == 0 ) {
			return undef unless exists $graph0{$id1} and exists $graphr0{$id2}; # This should not happen, otherwise bug in database
			push(@{$graph0{$id1}}, $id2);
			push(@{$graphr0{$id2}}, $id1);
		} else {
			return undef unless exists $graph1{$id1} and exists $graphr1{$id2}; # This should not happen, otherwise bug in database
			push(@{$graph1{$id1}}, $id2);
			push(@{$graphr1{$id2}}, $id1);
		}
	}

	my %dates;
	my %treer; # reverse

	my %djs_parent;
	my %djs_size;
	djs_makeset(\%djs_parent, \%djs_size, $_->{id}) foreach @{$emails};

	# Vertices not processed (with list of neighbors)
	my %output0;
	my %output1;

	$output0{$_} = { map { $_ => 1 } @{$graph0{$_}} } foreach keys %graph0;
	$output1{$_} = { map { $_ => 1 } @{$graph1{$_}} } foreach keys %graph1;

	# Modified topological sort, but from bottom of graph
	while ( %output0 or %output1 ) {

		my @keys0;
		my @keys1;

		foreach ( keys %output0, keys %output1 ) {
			push(@keys0, $_) unless $emails{$_}->{implicit};
			push(@keys1, $_) if $emails{$_}->{implicit};
		}

		my $id1;
		my $c1;

		# Choose vertex with smallest output degree, prefer non implicit
		# TODO: Instead sequence scan use heap, it has better time complexity
		foreach ( @keys0, @keys1 ) {
			my $c2 = 0;
			$c2 += scalar keys %{$output0{$_}} if exists $output0{$_};
			$c2 += scalar keys %{$output1{$_}} if exists $output1{$_};
			if ( not defined $id1 ) {
				$id1 = $_;
				$c1 = $c2;
				next;
			}
			if ( $c1 > $c2 ) {
				$id1 = $_;
				$c1 = $c2;
			}
		}

		# It should be zero, if not loop detected and all edges from this vertex will be cut
		delete $output0{$id1};
		delete $output1{$id1};

		# Remove all output edges to vertex $id1
		foreach ( @{$graphr0{$id1}}, @{$graphr1{$id1}} ) {
			my $id2 = $_;
			delete $output0{$id2}->{$id1} if exists $output0{$id2};
			delete $output1{$id2}->{$id1} if exists $output1{$id2};
		}

		# Add all output edges from vertex $id1 to final tree, prefer in-reply-to edges
		foreach ( @{$graph0{$id1}}, @{$graph1{$id1}} ) {
			my $id2 = $_;
			next if exists $treer{$id2};
			next if djs_find(\%djs_parent, \%djs_size, $id1) == djs_find(\%djs_parent, \%djs_size, $id2);
			djs_merge(\%djs_parent, \%djs_size, $id1, $id2);
			$treer{$id2} = $id1;
			if ( $emails{$id1}->{implicit} and defined $emails{$id2}->{date} ) {
				if ( ( not exists $dates{$id1} ) or ( $desc and $dates{$id1} < $emails{$id2}->{date} ) or ( not $desc and $dates{$id1} > $emails{$id2}->{date} ) ) {
					$dates{$id1} = $emails{$id2}->{date};
				}
			}
		}

	}

	my $root;

	# Select candidates for root
	my %processed;
	my @roots;

	foreach ( @{$emails} ) {
		my $id = $_->{id};
		next if $processed{$id};
		$processed{$id} = 1;
		my $next = 0;
		while ( $treer{$id} ) {
			$id = $treer{$id};
			$next = 1 if $processed{$id};
			last if $next;
			$processed{$id} = 1;
		}
		next if $next;
		push(@roots, $id);
	}

	return undef unless @roots; # This should not happen, otherwise bug in database

	# Set oldest email as root
	# In case that all candidates are implicit emails (with NULL date) first will be selected
	$root = $roots[0];
	my $date = "inf";
	foreach ( @roots ) {
		my $newdate = $emails{$_}->{date};
		$newdate = $dates{$_} unless defined $newdate;
		next unless defined $newdate;
		next unless $date > $newdate;
		$date = $newdate;
		$root = $_;
	}

	return undef unless defined $root; # This should not happen, otherwise bug

	# Add missing emails to root
	foreach ( keys %emails ) {
		next if exists $treer{$_};
		my $id1 = $root;
		my $id2 = $_;
		$treer{$id2} = $id1;
		if ( $emails{$id1}->{implicit} and defined $emails{$id2}->{date} ) {
			if ( ( not exists $dates{$id1} ) or ( $desc and $dates{$id1} < $emails{$id2}->{date} ) or ( not $desc and $dates{$id1} > $emails{$id2}->{date} ) ) {
				$dates{$id1} = $emails{$id2}->{date};
			}
		}
	}

	# Build direct (not reverse) tree
	my %tree = ( root => [$root], $root => [] );
	foreach ( @{$emails} ) {
		my $id2 = $_->{id};
		my $id1 = $treer{$id2};
		$tree{$id1} = [] unless $tree{$id1};
		push(@{$tree{$id1}}, $id2);
		$dates{$id2} = $emails{$id2}->{date} if not exists $dates{$id2} and defined $emails{$id2}->{date};
		$dates{$id2} = 0 unless defined $dates{$id2};
	}

	foreach ( keys %tree ) {
		my @arr;
		if ( $desc ) {
			@arr = sort { $dates{$b} <=> $dates{$a} } @{$tree{$_}};
		} else {
			@arr = sort { $dates{$a} <=> $dates{$b} } @{$tree{$_}};
		}
		$tree{$_} = \@arr;
	}

	# Remove implicit emails from root which are without replies
	my @subroots;
	foreach ( @{$tree{$root}} ) {
		next if $emails{$_}->{implicit} and not $tree{$_};
		push(@subroots, $_);
	}
	$tree{$root} = \@subroots;

	return (\%tree, \%emails);

}

sub db_replies($$;$) {

	my ($priv, $id, $up) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $ret;

	my $id1 = "1";
	my $id2 = "2";

	if ( not $up ) {
		$id1 = "2";
		$id2 = "1";
	}

	# Select all emails which are in-reply-to or references (up or down) to specified email
	$statement = qq(
		SELECT DISTINCT e2.id, e2.messageid, e2.implicit, e2.treeid, r.type
			FROM emails AS e1
			JOIN replies AS r ON r.emailid$id1 = e1.id
			JOIN emails AS e2 ON e2.id = r.emailid$id2
			WHERE e1.messageid = ?
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref();
	} or do {
		return undef;
	};

	return undef unless $ret;

	my @reply;
	my @references;

	foreach ( @{$ret} ) {
		my @data = @{$_};
		my $type = pop(@data);
		if ( $type == 0 ) {
			push(@reply, \@data);
		} elsif ( $type == 1 ) {
			push(@references, \@data);
		} else {
			next;
		}
	}

	if ( ( $up and ( @reply or @references ) ) or $priv->{config}->{nomatchsubject} ) {
		return (\@reply, \@references);
	}

	my $limit = "";
	if ( $up ) {
		$limit = "LIMIT 1";
	}

	my $hasreply1 = "";
	my $hasreply2 = "";
	if ( $up ) {
		$hasreply2 = "hasreply = 0 AND";
	} else {
		$hasreply1 = "hasreply = 0 AND";
	}

	$statement = qq(
		SELECT id, subjectid, date
			FROM emails
			WHERE
				implicit = 0 AND
				$hasreply1
				subjectid != 1 AND
				subjectid != 2 AND
				date IS NOT NULL AND
				messageid = ?
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref({});
	} or do {
		return (\@reply, \@references);
	};

	return (\@reply, \@references) unless ( $ret and @{$ret} );

	my $email = ${$ret}[0];

	# Select all emails which has same (non empty) subject as specified email, do not have in-reply-to header and are send before specified email
	$statement = qq(
		SELECT id, messageid, implicit, treeid
			FROM emails
			WHERE
				implicit = 0 AND
				date IS NOT NULL AND
				$hasreply2
				id != ? AND
				subjectid = ? AND
				date <= ?
			ORDER BY date
			$limit
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($email->{id}, $email->{subjectid}, $email->{date});
		$ret = $sth->fetchall_arrayref();
	} or do {
		return (\@reply, \@references);
	};

	return (\@reply, \@references) unless ( $ret and @{$ret} );

	push(@reply, @{$ret});
	return (\@reply, \@references);

}

sub db_roots($$;%) {

	my ($priv, $desc, %args) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $ret;

	if ( $desc ) {
		$desc = "DESC";
	} else {
		$desc = "";
	}

	my @args;

	my $where = "";
	my $limit = "";

	if ( exists $args{date1} ) {
		$where .= " t.date >= ? AND";
		push(@args, $args{date1});
	}

	if ( exists $args{date2} ) {
		$where .= " t.date < ? AND";
		push(@args, $args{date2});
	}

	if ( not $args{withspam} ) {
		$where .= " e.spam = 0 AND";
	}

	if ( $where ) {
		$where = "WHERE" . $where;
		$where =~ s/AND$//;
	}

	if ( exists $args{limit} ) {
		$limit .= "LIMIT ?";
		push(@args, $args{limit});
	}

	# NOTE: OFFSET can be specified only if LIMIT was specified
	if ( exists $args{limit} and exists $args{offset} ) {
		$limit .= " OFFSET ?";
		push(@args, $args{offset});
	}

	$statement = qq(
		SELECT t.emailid AS id, e.messageid AS messageid, t.date AS date, s.subject AS subject, t.id AS treeid, t.count AS count
			FROM trees AS t
			JOIN emails AS e ON e.id = t.emailid
			JOIN subjects AS s ON s.id = e.subjectid
			$where
			ORDER BY t.date $desc
			$limit
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(@args);
		$ret = $sth->fetchall_arrayref({});
	} or do {
		return undef;
	};

	return $ret;

}

sub email($$;$) {

	my ($priv, $id, $withspam) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $ret;

	if ( not $withspam ) {
		$withspam = "AND spam = 0";
	} else {
		$withspam = "";
	}

	$statement = qq(
		SELECT messageid, list, offset
			FROM emails
			WHERE implicit = 0 AND messageid = ?
			$withspam
			LIMIT 1
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_hashref("messageid");
	} or do {
		return undef;
	};

	return undef unless $ret and $ret->{$id};

	my $listname = $ret->{$id}->{list};
	my $offset = $ret->{$id}->{offset};

	my $list = PList::List::Binary->new($priv->{dir} . "/" . $listname, 0);
	return undef unless $list;

	return $list->readat($offset);

}

sub view($$;%) {

	my ($priv, $id, %args) = @_;

	my $pemail = $args{pemail};

	if ( not $pemail ) {
		$pemail = $priv->email($id, $args{withspam});
		return undef unless $pemail;
	}

	if ( not $args{nopregen} ) {

		my $dir = $priv->{dir};
		my $subdir = substr($id, 0, 2);
		my $file;

		if ( open($file, "<", "$dir/pregen/$subdir/$id.html") ) {

			my $str;

			binmode($file, ":raw");

			{
				local $/= undef;
				$str = <$file>;
			}

			close($file);
			return \$str;

		}

	}

	delete $args{pemail};
	delete $args{nopregen};

	return PList::Email::View::to_str($pemail, %args);

}

sub data($$$;$) {

	my ($priv, $id, $part, $fh) = @_;

	my $pemail = $priv->email($id);
	return undef unless $pemail;

	return $pemail->data($part, $fh);

}

sub setspam($$$) {

	my ($priv, $id, $val) = @_;

	my $dbh = $priv->{dbh};
	my $statement;
	my $ret;

	$statement = qq(
		SELECT id
			FROM emails
			WHERE messageid = ?
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref();
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	if ( not $ret or not $ret->[0] ) {
		warn "Email with id '$id' is not in database\n";
		return 0;
	}

	$statement = qq(
		UPDATE emails
			SET spam = ?
			WHERE messageid = ?
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($val, $id);
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	eval {
		$dbh->commit();
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	return 1;

}

sub delete($$) {

	my ($priv, $id) = @_;

	my $fh;
	if (not open($fh, ">>", $priv->{dir} . "/deleted")) {
		warn "Cannot open file deleted\n";
		return 0;
	}

	if (not flock($fh, 2)) {
		warn "Cannot lock file deleted\n";
		close($fh);
		return 0;
	}

	my $dbh = $priv->{dbh};
	my $statement;
	my $ret;
	my $rid;
	my $treeid;
	my $treecount;

	$statement = qq(
		SELECT id, messageid
			FROM emails
			WHERE implicit = 0 AND messageid = ?
			LIMIT 1
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_hashref("messageid");
	} or do {
		eval { $dbh->rollback(); };
		close($fh);
		return 0;
	};

	if ( not $ret or not $ret->{$id} ) {
		warn "Email with id '$id' is not in database\n";
		close($fh);
		return 0;
	}

	$rid = $ret->{$id}->{id};

	$statement = qq(
		SELECT id, count
			FROM trees
			WHERE emailid = ?
			LIMIT 1
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($rid);
		$ret = $sth->fetchall_hashref("id");
	} or do {
		eval { $dbh->rollback(); };
		close($fh);
		return 0;
	};

	if ( $ret and $ret->{$rid} ) {
		$treeid = $ret->{$rid}->{id};
		$treecount = $ret->{$rid}->{count};
	}

	$statement = qq(
		SELECT COUNT(*)
			FROM replies
			WHERE emailid2 = ?
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($rid);
		$ret = $sth->fetchall_arrayref();
	} or do {
		eval { $dbh->rollback(); };
		close($fh);
		return 0;
	};

	if ( not $ret or not @{$ret} or not ${$ret}[0] or not @{${$ret}[0]} ) {
		eval { $dbh->rollback(); };
		close($fh);
		return 0;
	}

	my $count = ${${$ret}[0]}[0];

	if ( defined $treeid and defined $treecount ) {
		if ( $treecount > 1 ) {
			$statement = qq(
				UPDATE trees
					SET
						emailid = (SELECT MIN(id) FROM emails WHERE id != ? AND treeid = ? AND date = (SELECT MIN(date) FROM emails WHERE id != ? AND implicit = 0 AND treeid = ?))
						date = (SELECT MIN(date) FROM emails WHERE id != ? AND implicit = 0 AND treeid = ?),
						count = (SELECT COUNT(*) FROM emails WHERE treeid = ?),
					WHERE
						id = ?
				;
			);
			eval {
				my $sth = $dbh->prepare_cached($statement);
				$sth->execute($treeid, $treeid, $treeid, $treeid, $treeid);
			} or do {
				eval { $dbh->rollback(); };
				return 0;
			};
		} else {
			$statement = qq(
				DELETE
					FROM trees
					WHERE id = ?
				;
			);
			eval {
				my $sth = $dbh->prepare_cached($statement);
				$sth->execute($treeid);
			} or do {
				eval { $dbh->rollback(); };
				return 0;
			};
		}
	}

	# Remove email from database or mark it as implicit (if some other email reference it)
	if ( $count > 0 ) {

		$statement = qq(
			UPDATE emails
				SET
					date = NULL,
					subjectid = 1,
					subject = NULL,
					list = NULL,
					offset = NULL,
					implicit = 1,
					hasreply = NULL
				WHERE messageid = ?
			;
		);

	} else {

		$statement = qq(
			DELETE
				FROM emails
				WHERE messageid = ?
			;
		);

	}

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
	} or do {
		eval { $dbh->rollback(); };
		close($fh);
		return 0;
	};

	eval {
		$dbh->commit();
	} or do {
		eval { $dbh->rollback(); };
		close($fh);
		return 0;
	};

	# Add message id of email to file deleted
	seek($fh, 0, 2);
	print $fh "$id\n";
	close($fh);

}

1;
