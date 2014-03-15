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
# id, messageid, date, subjectid(subjects), list, offset, implicit, hasreply
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

	my $driver = <$fh>;
	my $params = <$fh>;
	my $username = <$fh>;
	my $password = <$fh>;

	chop($driver) if $driver;
	chop($params) if $params;
	chop($username) if $username;
	chop($password) if $password;

	close($fh);

	my $dbh = db_connect($dir, $driver, $params, $username, $password);
	if ( not $dbh ) {
		return undef;
	}

	my $priv = {
		dir => $dir,
		dbh => $dbh,
		driver => $driver,
	};

	bless $priv, $class;

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
		$dbh->{AutoCommit} = 1; # NOTE: AutoCommit must be disabled when changing pragmas, otherwise foreign_keys will not be changed
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
			list		$text,
			offset		INTEGER,
			implicit	INTEGER NOT NULL,
			hasreply	INTEGER,
			UNIQUE (messageid $uniquesize) $ignoreconflict
		);
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
		CREATE TABLE address (
			id		INTEGER PRIMARY KEY NOT NULL $autoincrement,
			email		$text NOT NULL,
			name		$text NOT NULL,
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
		INSERT INTO subjects (id, subject)
			VALUES (1, NULL)
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
	} elsif ( not defined $params ) {
		$params = "";
	}

	if ( not defined $username ) {
		$password = undef;
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

	print $fh "$driver\n";
	print $fh "$params\n";
	print $fh "$username\n" if defined $username;
	print $fh "$password\n" if defined $password;
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
	my $subject = normalize_subject($header->{subject});

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
		$sth->execute($subject);
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
					list = ?,
					offset = ?,
					implicit = 0,
					hasreply = ?
				WHERE messageid = ?
			;
		);
	} else {
		$statement = qq(
			INSERT INTO emails (date, subjectid, list, offset, implicit, hasreply, messageid)
				VALUES (
					?,
					(SELECT id FROM subjects WHERE subject = ?),
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
		$sth->execute($date, $subject, $listfile, $offset, $hasreply, $id);
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	my @replies;

	if ( $reply and @{$reply} ) {
		push(@replies, [$id, $_, 0]) foreach ( @{$reply} );
	}
	if ( $references and @{$references} ) {
		push(@replies, [$id, $_, 1]) foreach ( @{$references} );
	}

	# Insert in-reply-to and references emails to database as implicit (if not exists)
	$statement = qq(
		INSERT INTO emails (messageid, subjectid, implicit)
			VALUES (?, 1, 1)
			$ignoreconflict
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute(${$_}[1]) foreach (@replies);
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
			push(@addressess, [$id, $1, $2, 0]);
		}
	}

	if ( $to and @{$to} ) {
		foreach ( @{$to} ) {
			$_ =~ /^(\S*) (.*)$/;
			push(@addressess, [$id, $1, $2, 1]);
		}
	}

	if ( $cc and @{$cc} ) {
		foreach ( @{$cc} ) {
			$_ =~ /^(\S*) (.*)$/;
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

sub db_email($$;$) {

	my ($priv, $id, $rid) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $email = { from => [], to => [], cc => [] };
	my $ret;

	my $where = "messageid";
	$where = "id" if $rid;

	# Select email with messageid
	$statement = qq(
		SELECT e.id, e.messageid, e.date, s.subject, e.list, e.offset, e.implicit, e.hasreply
			FROM emails AS e
			JOIN subjects AS s ON s.id = e.subjectid
			WHERE e.$where = ?
			LIMIT 1
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_hashref($where);
	} or do {
		eval { $dbh->rollback(); };
		return undef;
	};

	if ( not $ret or not $ret->{$id} ) {
		eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };
		return undef;
	}

	$email->{$_} = $ret->{$id}->{$_} foreach (keys %{$ret->{$id}});

	if ( $email->{implicit} ) {
		eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };
		return $email;
	}

	# Select from, to, cc for email
	$statement = qq(
		SELECT DISTINCT a.email, a.name, s.type
			FROM addressess AS s
			JOIN address AS a ON a.id = s.addressid
			WHERE emailid = ?
		;
	);

	eval {
		my $sth = $dbh->prepare_cached($statement);
		$sth->execute($email->{id});
		$ret = $sth->fetchall_arrayref();
	} or do {
		eval { $dbh->rollback(); };
		return undef;
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

	return $email unless $ret;

	foreach ( @{$ret} ) {
		my $type = $_->[2];
		my $array;
		if ( $type == 0 ) {
			$array = $email->{from};
		} elsif ( $type == 1 ) {
			$array = $email->{to};
		} elsif ( $type == 2 ) {
			$array = $email->{cc};
		} else {
			next;
		}
		push(@{$array}, [$_->[0], $_->[1]]);
	}

	return $email;

}

sub db_emails($;%) {

	my ($priv, %args) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my @args;
	my $ret;

	if ( exists $args{subject} ) {
		$args{subject} = normalize_subject($args{subject});
	}

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
	$statement = "SELECT DISTINCT e.id, e.messageid, e.date, s.subject, e.list, e.offset, e.implicit, e.hasreply FROM emails AS e";
	$statement .= " JOIN subjects AS s ON s.id = e.subjectid";

	if ( exists $args{email} or exists $args{name} ) {
		$statement .= " JOIN addressess AS ss ON ss.emailid = e.id JOIN address AS a ON a.id = ss.addressid";
	}

	if ( exists $args{date1} or exists $args{date2} or exists $args{subject} or exists $args{email} or exists $args{name} or exists $args{type} ) {
		$statement .= " WHERE";
	}

	if ( exists $args{date1} ) {
		$statement .= " e.date >= ? AND";
		push(@args, $args{date1});
	}

	if ( exists $args{date2} ) {
		$statement .= " e.date < ? AND";
		push(@args, $args{date2});
	}

	if ( exists $args{subject} ) {
		$statement .= " s.subject LIKE ? AND";
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

	if ( exists $args{type} ) {
		$statement .= " ss.type = ? AND";
		push(@args, $args{type});
	}

	$statement =~ s/AND$//;

	$statement .= " ORDER BY e.date";

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
		$ret = $sth->fetchall_arrayref();
	} or do {
		eval { $dbh->rollback(); };
		return undef;
	};

	eval { $dbh->commit(); } or do { eval { $dbh->rollback(); }; };

	return $ret;

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
		SELECT DISTINCT e2.id, e2.messageid, r.type, e2.implicit
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
		my $mid = [${$_}[0], ${$_}[1], ${$_}[3]];
		my $type = ${$_}[2];
		if ( $type == 0 ) {
			push(@reply, $mid);
		} elsif ( $type == 1 ) {
			push(@references, $mid);
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

	# Select all emails which has same subject as specified email, do not have in-reply-to header and are send before specified email
	$statement = qq(
		SELECT DISTINCT e2.id, e2.messageid, e2.implicit
			FROM emails AS e1
			JOIN emails AS e2 ON e2.subjectid = e1.subjectid
			WHERE e1.id != e2.id AND e1.implicit = 0 AND e2.implicit = 0 AND e$id1.hasreply = 0 AND e1.date IS NOT NULL AND e2.date IS NOT NULL AND e$id1.date >= e$id2.date AND e1.$where = ?
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

sub db_subtree($$;$$$) {

	my ($priv, $id, $desc, $rid, $limit) = @_;

	my %tree = ( root => [] );
	my %treerev;
	my %tree2;
	my %processed = ( root => 1 );
	my @stack1 = (["root", $id, 0]);
	my @stack2;
	my @stack3;

	my $arri = 1;
	$arri = 0 if $rid;

	while ( scalar @stack1 or scalar @stack2 or scalar @stack3 ) {

		my $m;
		my $s3;
		if ( scalar @stack1 ) {
			$m = pop(@stack1);
		} elsif ( scalar @stack2 ) {
			$m = pop(@stack2);
		} else {
			$m = pop(@stack3);
			$s3 = 1;
		}

		my ($up, $tid, $len) = @{$m};

		next if $processed{$tid};

		next if defined $limit and $len > $limit;

		$tree{$tid} = [] unless $tree{$tid};

		if ( $s3 ) {
			$tree2{$up} = [] unless $tree2{$up};
			push(@{$tree2{$up}}, $tid);
		} else {
			$treerev{$tid} = [] unless $treerev{$tid};
			$processed{$tid} = 1;
			push(@{$tree{$up}}, $tid);
			push(@{$treerev{$tid}}, $up);
		}

		my ($reply, $references) = $priv->db_replies($tid, 0, $desc, $rid);

		if ( scalar @{$reply} ) {
			push(@stack1, [$tid, ${$_}[$arri], $len+1]) foreach ( @{$reply} );
			if ( not defined $limit ) {
				push(@stack2, [$tid, ${$_}[$arri], $len+1]) foreach ( @{$references} );
			}
		} else {
			push(@stack3, [$tid, ${$_}[$arri], $len+1]) foreach ( @{$references} );
		}

	}

	foreach my $up ( keys %tree2 ) {
		foreach my $tid ( @{$tree2{$up}} ) {
			if ( not exists $treerev{$tid} ) {
				push(@{$tree{$up}}, $tid);
			}
		}
	}

	return \%tree;

}

sub db_tree($$;$$$$) {

	my ($priv, $id, $desc, $rid, $limitup, $limitdown) = @_;

	my $tid = $id;
	my $impl = 0;

	my %processed;

	my $arri = 1;
	$arri = 0 if $rid;

	my $count = 0;

	while ( 1 ) {

		last if defined $limitup and ++$count > $limitup;

		my ($reply, $references) = $priv->db_replies($tid, 1, 0, $rid);

		$processed{$tid} = 1;

		my $newtid;
		my $newimpl = 0;

		foreach ( @{$reply} ) {
			if ( not ${$_}[2] and not $processed{${$_}[$arri]} ) {
				$newtid = ${$_}[$arri];
				last;
			}
		}

		if ( $newtid ) {
			$tid = $newtid;
			$impl = $newimpl;
			redo;
		}

		foreach ( @{$references} ) {
			if ( not ${$_}[2] and not $processed{${$_}[$arri]} ) {
				$newtid = ${$_}[$arri];
				last;
			}
		}

		if ( $newtid ) {
			$tid = $newtid;
			$impl = $newimpl;
			redo;
		}

		$newimpl = 1;

		foreach ( @{$reply} ) {
			if ( not $processed{${$_}[$arri]} ) {
				$newtid = ${$_}[$arri];
				last;
			}
		}

		if ( $newtid ) {
			$tid = $newtid;
			$impl = $newimpl;
			redo;
		}

		foreach ( @{$references} ) {
			if ( not $processed{${$_}[$arri]} ) {
				$newtid = ${$_}[$arri];
				last;
			}
		}

		if ( $newtid ) {
			$tid = $newtid;
			$impl = $newimpl;
			redo;
		}

		last;

	}

	my $limit;

	if ( defined $limitup and $limitdown ) {
		$limit = $limitup + $limitdown;
	} elsif ( defined $limitdown ) {
		$limit = $limitdown;
	}

	my $tree = $priv->db_subtree($tid, $desc, $rid, $limit);

	if ( $impl ) {
		my $root = ${$tree->{root}}[0];
		if ( $id ne $root and scalar @{$tree->{$root}} == 1 ) {
			$tree->{root} = $tree->{$root};
			delete $tree->{$root};
		}
	}

	return $tree;

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

	my $date = "";
	my $havingdate = "";
	my $limit = "";

	if ( exists $args{date1} ) {
		$date .= "AND realdate >= ?";
		push(@args, $args{date1});
	}

	if ( exists $args{date2} ) {
		$date .= "AND realdate < ?";
		push(@args, $args{date2});
	}

	if ( exists $args{date1} and exists $args{date2} ) {
		$havingdate = "HAVING realdate >= ? AND realdate < ?";
		push(@args, $args{date1}, $args{date2});
	} elsif ( exists $args{date1} ) {
		$havingdate = "HAVING realdate >= ?";
		push(@args, $args{date1});
	} elsif ( exists $args{date2} ) {
		$havingdate = "HAVING realdate < ?";
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
		SELECT e1.id, e1.messageid, e1.realdate, s.subject, e1.implicit
			FROM (
				SELECT e1.id, e1.messageid, e1.date AS realdate, e1.subjectid, e1.implicit
					FROM emails AS e1,
						(
							SELECT subjectid, MIN(date) AS date2
								FROM emails
								WHERE hasreply = 0 AND subjectid != 0
								GROUP BY subjectid
						) AS e2
					WHERE
						e1.subjectid = e2.subjectid AND
						e1.date = e2.date2
						$date
			) AS e1
			JOIN subjects AS s ON s.id = e1.subjectid
		UNION
		SELECT e1.id, e1.messageid, MIN(e2.date) AS realdate, s.subject, e1.implicit
			FROM emails AS e1
			LEFT OUTER JOIN replies AS r1 ON r1.emailid2 = e1.id
			LEFT OUTER JOIN emails AS e2 ON e2.id = r1.emailid1
			JOIN subjects AS s ON s.id = e2.subjectid
			WHERE
				e1.implicit = 1 AND
				e2.implicit = 0 AND
				EXISTS (
					SELECT * FROM replies AS r2
						WHERE r2.emailid2 = e1.id AND r2.type = 0
				)
			GROUP BY e1.id
			$havingdate
		ORDER BY realdate $desc
		$limit
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
