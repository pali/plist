package PList::Index;

use strict;
use warnings;

use PList::Email::Binary;
use PList::Email::View;

use PList::List::Binary;

use Time::Piece;
use File::Path qw(make_path);
use DBI;
use Cwd;

# directory structure:
#
# [0-9]{5}.list
# deleted
# config

# SQL tables:
#
# emails:
# id, messageid, date, subjectid(subjects), subject, treeid, list, offset, implicit, hasreply
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

	my $driver;
	my $params = "";
	my $username;
	my $password;

	my $description;

	while (<$fh>) {
		next if $_ =~ /^\s*#/;
		next unless $_ =~ /^\s*([^=]+)=(.*)$/;
		$driver = $2 if $1 eq "driver";
		$params = $2 if $1 eq "params";
		$username = $2 if $1 eq "username";
		$password = $2 if $1 eq "password";
		$description = $2 if $1 eq "description";
	}

	close($fh);

	if ( not defined $driver ) {
		warn "Driver was not specified in config file\n";
		return undef;
	}

	my $dbh = db_connect($dir, $driver, $params, $username, $password);
	if ( not $dbh ) {
		return undef;
	}

	my $priv = {
		dir => $dir,
		dbh => $dbh,
		driver => $driver,
		description => $description,
	};

	bless $priv, $class;

}

sub description($) {

	my ($priv) = @_;
	return $priv->{description};

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

	# NOTE: Higher values are not possible for MySQL INNODB engline
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

	# NOTE: Equvalents for MySQL are in INSERT/UPDATE SQL statements
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
		CREATE INDEX emailsimplicit ON emails(implicit);
	);
	eval { $dbh->do($statement); } or do { eval { $dbh->rollback(); }; return 0; };

	$statement = qq(
		CREATE INDEX emailshasreply ON emails(hasreply);
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

sub create($;$$$$) {

	my ($dir, $driver, $params, $username, $password) = @_;

	if ( not $driver ) {
		$driver = "SQLite";
	}

	if ( $driver eq "SQLite" and not $params ) {
		$params = "sqlite.db";
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

	print $fh "driver=$driver\n";
	print $fh "params=$params\n" if defined $params;
	print $fh "username=$username\n" if defined $username;
	print $fh "password=$password\n" if defined $password;
	close($fh);

	return 1;

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

# Remove all leadings strings RE: FW: FWD: and mailinglist name in square brackets
# After this normalization subject can be used for fiding reply emails if in-reply-to header is missing
sub normalize_subject($) {

	my ($subject) = @_;

	return "" unless defined $subject;
	$subject =~ s/^\s*(?:(?:(Re|Fw|Fwd):\s*)*)(?:(\[[^\]]+\]\s*(?:(Re|Fw|Fwd):\s*)+)*)//i;

	return $subject;

}

sub add_email($$) {

	my ($priv, $pemail) = @_;

	my $header = $pemail->header("0");

	if ( not $header ) {
		warn "Corrupted email\n";
		return 0;
	}

	my $dbh = $priv->{dbh};
	my $driver = $priv->{driver};

	my $id = $header->{id};
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
		warn "Email with id '$id' already in database\n";
		return 0;
	}

	if ( $ret and $ret->{$id} ) {
		$rid = $ret->{$id}->{id};
	}

	# TODO: Increase listfile name number if file is too big

	my $listfile = "00000.list";
	my $offset;

	my $list = new PList::List::Binary($priv->{dir} . "/" . $listfile, 1);
	if ( not $list ) {
		warn "Cannot open listfile '$listfile'\n";
		eval { $dbh->rollback(); };
		return 0;
	};

	$offset = $list->append($pemail);
	if ( not defined $offset ) {
		warn "Cannot append email to listfile '$listfile'\n";
		eval { $dbh->rollback(); };
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
					hasreply = ?
				WHERE messageid = ?
			;
		);
	} else {
		$statement = qq(
			INSERT INTO emails (date, subjectid, subject, list, offset, implicit, hasreply, messageid)
				VALUES (
					?,
					(SELECT id FROM subjects WHERE subject = ?),
					?,
					?,
					?,
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

	$statement = "SELECT MAX(treeid)+1 FROM emails;";

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
	}

	eval {
		$dbh->commit();
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	return 1;

}

sub add_list($$) {

	my ($priv, $list) = @_;

	my $count = 0;
	my $total = 0;

	while ( not $list->eof() ) {
		++$total;
		my $pemail = $list->readnext();
		if ( not $pemail ) {
			warn "Cannot read email\n";
			next;
		}
		if ( not $priv->add_email($pemail) ) {
			warn "Cannot add email with id '" . $pemail->header("0")->{id} . "'\n";
			next;
		}
		++$count;
	}

	return ($count, $total);

}

sub db_date($$;$$) {

	my ($priv, $oformat, $iformat, $value) = @_;

	my $dbh = $priv->{dbh};
	my $driver = $priv->{driver};

	my $statement;
	my @args = ($oformat);
	my $ret;

	my $func = "date";
	$func = "FROM_UNIXTIME(date, ?)" if $driver eq "mysql";
	$func = "strftime(?, date, \"unixepoch\")" if $driver eq "SQLite";

	my $cond = "";
	if ( defined $iformat and defined $value ) {
		$cond = " AND $func = ?";
		push(@args, $iformat, $value);
	}

	$statement = qq(
		SELECT DISTINCT $func
			FROM emails
			WHERE date IS NOT NULL
			$cond
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(@args);
		$ret = $sth->fetchall_arrayref();
	} or do {
		eval { $dbh->rollback(); };
		return undef;
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

	return $ret;

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
	$statement .= " SELECT e.id AS id, e.messageid AS messageid, e.date AS date, e.subject AS subject, e.treeid AS treeid, af.email AS email, af.name AS name, e.list AS list, e.offset AS offset, e.implicit AS implicit, e.hasreply AS hasreply FROM emails AS e";
	$statement .= " LEFT OUTER JOIN addressess AS ssf ON ssf.emailid = e.id LEFT OUTER JOIN address AS af ON af.id = ssf.addressid";

	if ( exists $args{email} or exists $args{name} ) {
		$statement .= " JOIN addressess AS ss ON ss.emailid = e.id JOIN address AS a ON a.id = ss.addressid";
	}

	$statement .= " WHERE";

	if ( exists $args{id} ) {
		$statement .= " e.id = ? AND";
		push(@args, $args{id});
	}

	if ( exists $args{messageid} ) {
		$statement .= " e.messageid = ? AND";
		push(@args, $args{messageid});
	}

	if ( exists $args{treeid} ) {
		$statement .= " e.treeid = ? AND";
		push(@args, $args{treeid});
	}

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

	if ( exists $args{subject} ) {
		$statement .= " e.subject LIKE ? AND";
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
		eval { $dbh->rollback(); };
		return undef;
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

	return $ret;

}

sub db_emails_str($$;%) {

	my ($priv, $str, %args) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my @args;
	my $ret;

	# Select all email messageids which match conditions
	$statement = "SELECT ee.id AS id, ee.messageid AS messageid, ee.date AS date, ee.subject AS subject, ee.treeid AS treeid, ee.email AS email, ee.name AS name, ee.list AS list, ee.offset AS offset, ee.implicit AS implicit, ee.hasreply AS hasreply FROM (";
	$statement .= " SELECT * FROM emails AS e";
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
		eval { $dbh->rollback(); };
		return undef;
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

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
		eval { $dbh->rollback(); };
		return undef;
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

	return undef unless $ret and $ret->[0];
	return $ret->[0]->[0];

}

sub db_graph($$;$) {

	my ($priv, $treeid, $desc) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $ret;

	if ( $desc ) {
		$desc = "DESC";
	} else {
		$desc = "";
	}

	$statement = qq(
		SELECT e1.id AS id1, e2.id AS id2, r.type AS type
			FROM emails AS e1
			JOIN replies AS r ON r.emailid2 = e1.id
			JOIN emails AS e2 ON e2.id = r.emailid1
			WHERE e1.treeid = ?
			ORDER BY r.type, e1.date, e2.date $desc
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($treeid);
		$ret = $sth->fetchall_arrayref({});
	} or do {
		eval { $dbh->rollback(); };
		return undef;
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

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

	my $emails = $priv->db_emails(treeid => $treeid, desc => $desc);
	return undef unless $emails and @{$emails};

	my $graph = $priv->db_graph($treeid, $desc);
	return undef unless $graph;

	my %emails;
	$emails{$_->{id}} = $_ foreach @{$emails};

	my %graphr; # reverse

	foreach ( @{$graph} ) {
		my $id1 = $_->{id1};
		my $id2 = $_->{id2};
		my $type = $_->{type};
		$graphr{$id2} = [] unless $graphr{$id2};
		push(@{$graphr{$id2}}, [$id1, $type]);
	}

	# Make sure that every email has only one in-reply-to edge (other set to references)
	foreach ( keys %graphr ) {
		my $reply = 0;
		foreach ( @{$graphr{$_}} ) {
			next if $_->[1] != 0;
			if ( not $reply ) {
				$reply = 1;
			} else {
				$_->[1] = 1;
			}
		}
	}

	my %dates;
	my %treer; # reverse

	my %djs_parent;
	my %djs_size;
	djs_makeset(\%djs_parent, \%djs_size, $_->{id}) foreach @{$emails};

	if ( (scalar keys %graphr) != 0 ) {

		# First add in-reply-to edges
		foreach ( @{$emails} ) {
			my $id2 = $_->{id};
			next if exists $treer{$id2};
			next unless $graphr{$id2};
			foreach ( @{$graphr{$id2}} ) {
				my $id1 = $_->[0];
				my $type = $_->[1];
				next if $type != 0;
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

	}

	if ( (scalar keys %graphr) != 0 and (scalar keys %graphr) != (scalar keys %treer) + 1 ) {

		# Then add unambiguous references edges
		foreach ( @{$emails} ) {
			my $id2 = $_->{id};
			next if exists $treer{$id2};
			next unless $graphr{$id2};
			my $pos = -1;
			my $i = -1;
			foreach ( @{$graphr{$id2}} ) {
				++$i;
				my $id1 = $_->[0];
				my $type = $_->[1];
				next if $type != 1;
				if ( $pos != -1 ) {
					$pos = -1;
					last;
				}
				$pos = $i;
			}
			my $id1 = $graphr{$id2}->[$pos];
			if ( djs_find(\%djs_parent, \%djs_size, $id1) != djs_find(\%djs_parent, \%djs_size, $id2) ) {
				djs_merge(\%djs_parent, \%djs_size, $id1, $id2);
				$treer{$id2} = $id1;
				if ( $emails{$id1}->{implicit} and defined $emails{$id2}->{date} ) {
					if ( ( not exists $dates{$id1} ) or ( $desc and $dates{$id1} < $emails{$id2}->{date} ) or ( not $desc and $dates{$id1} > $emails{$id2}->{date} ) ) {
						$dates{$id1} = $emails{$id2}->{date};
					}
				}
			}
		}

	}

	my $root;

	if ( (scalar keys %graphr) != (scalar keys %treer) + 1 ) {

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
		# In case that all candicates are implicit emails (with NULL date) first will be selected
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

		# TODO: add other references edges

	} else {

		# Set root from treer (there is only one)
		foreach ( keys %treer ) {
			next if $treer{$_};
			$root = $_;
			last;
		}

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

sub db_replies($$;$$$) {

	my ($priv, $id, $up, $desc, $rid) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $ret;

	my $id1 = "1";
	my $id2 = "2";

	if ( not $up ) {
		$id1 = "2";
		$id2 = "1";
	}

	if ( $desc ) {
		$desc = "DESC";
	} else {
		$desc = "";
	}

	my $where = "messageid";
	$where = "id" if ( $rid );

	# Select all emails which are in-reply-to or references (up or down) to specified email
	$statement = qq(
		SELECT DISTINCT e2.id, e2.messageid, e2.implicit, e2.treeid, r.type
			FROM emails AS e1
			JOIN replies AS r ON r.emailid$id1 = e1.id
			JOIN emails AS e2 ON e2.id = r.emailid$id2
			WHERE e1.$where = ?
			ORDER BY e2.date $desc
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref();
	} or do {
		eval { $dbh->rollback(); };
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

	if ( $up and ( @reply or @references ) ) {
		eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };
		return (\@reply, \@references);
	}

	my $limit = "";
	if ( $up ) {
		$limit = "LIMIT 1";
		$desc = "";
	}

	# Select all emails which has same (non empty) subject as specified email, do not have in-reply-to header and are send before specified email
	$statement = qq(
		SELECT DISTINCT e2.id, e2.messageid, e2.implicit, e2.treeid
			FROM emails AS e1
			JOIN emails AS e2 ON e2.subjectid = e1.subjectid
			WHERE
				e1.id != e2.id AND
				e1.implicit = 0 AND
				e2.implicit = 0 AND
				e$id1.hasreply = 0 AND
				e1.subjectid != 1 AND
				e1.subjectid != 2 AND
				e1.date IS NOT NULL AND
				e2.date IS NOT NULL AND
				e$id1.date >= e$id2.date AND
				e1.$where = ?
			ORDER BY e2.date $desc
			$limit
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref();
	} or do {
		eval { $dbh->rollback(); };
		return (\@reply, \@references);
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

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

	my $having = "";
	my $limit = "";

	if ( exists $args{date1} and exists $args{date2} ) {
		$having = "HAVING MIN(e.date) >= ? AND MIN(e.date) < ?";
		push(@args, $args{date1}, $args{date2});
	} elsif ( exists $args{date1} ) {
		$having = "HAVING MIN(e.date) >= ?";
		push(@args, $args{date1});
	} elsif ( exists $args{date2} ) {
		$having = "HAVING MIN(e.date) < ?";
		push(@args, $args{date2});
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
		SELECT e.id AS id, e.messageid AS messageid, MIN(e.date) AS date, s.subject AS subject, e.treeid AS treeid, COUNT(treeid) AS count
			FROM emails AS e
			JOIN subjects AS s ON s.id = e.subjectid
			WHERE implicit = 0
			GROUP BY treeid
			$having
			ORDER BY MIN(date) $desc
			$limit
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(@args);
		$ret = $sth->fetchall_arrayref({});
	} or do {
		eval { $dbh->rollback(); };
		return undef;
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

	return $ret;

}

sub email($$) {

	my ($priv, $id) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $ret;

	$statement = qq(
		SELECT messageid, list, offset
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
		return undef;
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

	return undef unless $ret and $ret->{$id};

	my $listname = $ret->{$id}->{list};
	my $offset = $ret->{$id}->{offset};

	my $list = new PList::List::Binary($priv->{dir} . "/" . $listname, 0);
	return undef unless $list;

	return $list->readat($offset);

}

sub view($$;%) {

	my ($priv, $id, %args) = @_;

	my $pemail = $priv->email($id);
	return undef unless $pemail;

	return PList::Email::View::to_str($pemail, %args);

}

sub data($$$;$) {

	my ($priv, $id, $part, $fh) = @_;

	my $pemail = $priv->email($id);
	return undef unless $pemail;

	return $pemail->data($part, $fh);

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
		SELECT COUNT(*)
			FROM replies
			WHERE emailid2 = ?
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
