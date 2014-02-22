package PList::Index;

use strict;
use warnings;

use PList::Email::Binary;
use PList::Email::View;

use PList::List::Binary;

use Time::Piece;
use File::Path qw(make_path);
use DBI;

# directory structure:
#
# [0-9]{5}.list
# deleted
# config

# SQL tables:
#
# emails:
# id, messageid, date, subjectid(subjects)
#
# reply:
# id, emailid1(emails), emailid2(emails)
#
# references:
# id, emailid1(emails), emailid2(emails)
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

	my $datasource = <$fh>;
	my $username = <$fh>;
	my $password = <$fh>;

	chop($datasource);
	chop($username);
	chop($password);

	close($fh);

	my $dbh = DBI->connect($datasource, $username, $password, { RaiseError => 1, AutoCommit => 0 });
	if ( not $dbh ) {
		return undef;
	}

	my $priv = {
		dir => $dir,
		dbh => $dbh,
	};

	bless $priv, $class;

}

sub DESTROY($) {

	my ($priv) = @_;

	my $dbh = $priv->{dbh};
	$dbh->disconnect();

}

sub create_tables($) {

	my ($dbh) = @_;

	my $statement;

	$statement = qq(
		CREATE TABLE subjects (
			id		INTEGER PRIMARY KEY NOT NULL,
			subject		TEXT UNIQUE ON CONFLICT IGNORE
		);
	);
	return 0 unless $dbh->do($statement);

	$statement = qq(
		CREATE TABLE emails (
			id		INTEGER PRIMARY KEY NOT NULL,
			messageid	TEXT NOT NULL UNIQUE,
			date		INTEGER,
			subjectid	INTEGER,
			list		TEXT,
			offset		INTEGER,
			implicit	INTEGER,
			hasreply	INTEGER,
			FOREIGN KEY(subjectid) REFERENCES subjects(id)
		);
	);
	return 0 unless $dbh->do($statement);

	$statement = qq(
		CREATE TABLE replies (
			id		INTEGER PRIMARY KEY NOT NULL,
			emailid1	INTEGER NOT NULL,
			emailid2	INTEGER NOT NULL,
			type		INTEGER NOT NULL,
			UNIQUE (emailid1, emailid2, type) ON CONFLICT IGNORE,
			FOREIGN KEY(emailid1) REFERENCES emails(id),
			FOREIGN KEY(emailid2) REFERENCES emails(id)
		);
	);
	return 0 unless $dbh->do($statement);

	$statement = qq(
		CREATE TABLE address (
			id		INTEGER PRIMARY KEY NOT NULL,
			email		TEXT NOT NULL,
			name		TEXT NOT NULL,
			UNIQUE (email, name) ON CONFLICT IGNORE
		);
	);
	return 0 unless $dbh->do($statement);

	$statement = qq(
		CREATE TABLE addressess (
			id		INTEGER PRIMARY KEY NOT NULL,
			emailid		INTEGER NOT NULL,
			addressid	INTEGER NOT NULL,
			type		INTEGER NOT NULL,
			UNIQUE (emailid, addressid, type) ON CONFLICT IGNORE,
			FOREIGN KEY(emailid) REFERENCES emails(id),
			FOREIGN KEY(addressid) REFERENCES address(id)
		);
	);
	return 0 unless $dbh->do($statement);

	$statement = qq(
		INSERT INTO subjects (id, subject)
			VALUES (0, NULL)
		;
	);
	return 0 unless $dbh->do($statement);

	return 1;

}

sub create($$$$) {

	my ($dir, $datasource, $username, $password) = @_;

	my $dbh;
	my $statement;
	my $ret;

	if ( not make_path($dir) ) {
		warn "Cannot create dir $dir\n";
		return 0;
	}

	$dbh = DBI->connect($datasource, $username, $password);
	if ( not $dbh ) {
		return 0;
	}

	$ret = create_tables($dbh);

	$dbh->disconnect();

	if ( not $ret ) {
		return 0;
	}

	my $fh;
	if ( not open($fh, ">", $dir . "/config") ) {
		warn "Cannot create config file\n";
		return 0;
	}

	print $fh "$datasource\n";
	print $fh "$username\n";
	print $fh "$password\n";
	close($fh);

	return 1;

}

sub regenerate($) {

	my ($priv) = @_;

}

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

	my $id = $header->{id};

	my $statement;
	my $sth;
	my $ret;

	$statement = qq(
		SELECT messageid
			FROM emails
			WHERE implicit = 0 AND messageid = ?
			LIMIT 1
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_hashref("messageid");
	} or do {
		eval { $dbh->rollback(); };
		return undef;
	};

	if ( $ret and $ret->{$id} ) {
		warn "Email with id '$id' already in database, skipping\n";
		return 0;
	}

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
	my $subject = normalize_subject($header->{subject});
	my $date;

	eval { $date = Time::Piece->strptime($header->{date}, "%Y-%m-%d %H:%M:%S %z") };
	$date = $date->epoch() if $date;
	$date = undef unless $date;

	$statement = qq(
		INSERT INTO subjects (subject)
			VALUES (?)
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($subject);
	} or do {
		eval { $dbh->rollback(); };
		return 0;
	};

	my $hasreply = 0;
	$hasreply = 1 if $reply and @{$reply};

	$statement = qq(
		INSERT OR REPLACE INTO emails (messageid, date, subjectid, list, offset, implicit, hasreply)
			VALUES (
				?,
				?,
				(SELECT id FROM subjects WHERE subject = ?),
				?,
				?,
				0,
				?
			)
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($id, $date, $subject, $listfile, $offset, $hasreply);
	} or do {
		warn "";
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

	$statement = qq(
		INSERT OR IGNORE INTO emails (messageid, subjectid, implicit)
			VALUES (?, 0, 1)
		;
	);

#	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute(@{$_}[1]) foreach (@replies);
#	} or do {
#		eval { $dbh->rollback(); };
#		return 0;
#	};

	$statement = qq(
		INSERT INTO replies (emailid1, emailid2, type)
			VALUES (
				(SELECT id FROM emails WHERE messageid = ?),
				(SELECT id FROM emails WHERE messageid = ?),
				?
			)
		;
	);

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

	$statement = qq(
		INSERT INTO address (email, name)
			VALUES (?, ?)
		;
	);

#	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute(${$_}[1], ${$_}[2]) foreach (@addressess);
#	} or do {
#		eval { $dbh->rollback(); };
#		return 0;
#	};

	$statement = qq(
		INSERT INTO addressess (emailid, addressid, type)
			VALUES (
				(SELECT id FROM emails WHERE messageid = ?),
				(SELECT id FROM address WHERE email = ? AND name = ?),
				?
			)
		;
	);

#	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute(@{$_}) foreach (@addressess);
#	} or do {
#		eval { $dbh->rollback(); };
#		return 0;
#	};

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
			warn "Cannot add email\n";
			next;
		}
		++$count;
	}

	return ($count, $total);

}

sub db_email($$) {

	my ($priv, $id) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $sth;
	my $email = { from => [], to => [], cc => [] };
	my $ret;

	$statement = qq(
		SELECT e.id, e.messageid, e.date, s.subject, e.list, e.offset, e.implicit, e.hasreply
			FROM emails AS e
			JOIN subjects AS s ON s.id = e.subjectid
			WHERE e.messageid = ?
			LIMIT 1
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_hashref("messageid");
	} or do {
		return undef;
	};

	return undef unless $ret and $ret->{$id};

	$email->{$_} = $ret->{$id}->{$_} foreach (keys %{$ret->{$id}});

	return $email if $email->{implicit};

	$statement = qq(
		SELECT DISTINCT a.email, a.name, s.type
			FROM addressess AS s
			JOIN address AS a ON a.id = s.addressid
			WHERE emailid = ?
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($email->{id});
		$ret = $sth->fetchall_arrayref();
	} or do {
		return undef;
	};

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
	my $sth;
	my $ret;

	if ( exists $args{subject} ) {
		$args{subject} = normalize_subject($args{subject});
	}

	$statement = "SELECT DISTINCT e.messageid FROM emails AS e";

	if ( exists $args{subject} ) {
		$statement .= " JOIN subjects AS s ON s.id = e.subjectid";
	}

	if ( exists $args{email} or exists $args{name} ) {
		$statement .= " JOIN addressess AS s ON s.emailid = e.id JOIN address AS a ON a.id = s.addressid";
	}

	if ( exists $args{date1} or exists $args{date2} or exists $args{subject} or exists $args{email} or exists $args{name} ) {
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
		$statement .= " s.subject LIKE %?% AND";
		push(@args, $args{subject});
	}

	if ( exists $args{email} ) {
		$statement .= " a.email LIKE %?% AND";
		push(@args, $args{email});
	}

	if ( exists $args{name} ) {
		$statement .= " a.name LIKE %?% AND";
		push(@args, $args{name});
	}

	$statement =~ s/AND$//;

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute(@args);
		$ret = $sth->fetchall_arrayref();
	} or do {
		return undef;
	};

	return undef unless $ret;
	return map { ${$_}[0] } @{$ret};

}

sub db_replies($$$) {

	my ($priv, $id, $up) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $sth;
	my $ret;

	my $id1;
	my $id2;
	if ( $up ) {
		$id1 = "1";
		$id2 = "2";
	} else {
		$id1 = "2";
		$id2 = "1";
	}

	$statement = qq(
		SELECT DISTINCT e2.messageid, r.type
			FROM emails AS e1
			JOIN replies AS r ON r.emailid$id1 = e1.id
			JOIN emails AS e2 ON e2.id = r.emailid$id2
			WHERE e1.messageid = ?
			ORDER BY e2.date
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref();
	} or do {
		return undef;
	};

	return undef unless $ret;

	my @reply;
	my @references;

	foreach ( @{$ret} ) {
		my $mid = ${$_}[0];
		my $type = ${$_}[1];
		if ( $type == 0 ) {
			push(@reply, $mid);
		} elsif ( $type == 1 ) {
			push(@references, $mid);
		} else {
			next;
		}
	}

	return (\@reply, \@references) if ( $up and scalar @reply != 0 );

	$statement = qq(
		SELECT e2.messageid
			FROM emails AS e1
			JOIN emails AS e2 ON e2.subjectid = e1.subjectid
			WHERE e1.id != e2.id AND e$id2.hasreply = 0 AND e1.date IS NOT NULL AND e2.date IS NOT NULL AND e$id1.date >= e$id2.date AND e1.messageid = ?
			ORDER BY e2.date
			LIMIT 1
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref();
	} or do {
		return (\@reply, \@references);
	};

	return (\@reply, \@references) if ( not $ret or scalar @{$ret} == 0 );

	push(@reply, ${@{$ret}}[0]);
	return (\@reply, \@references);

}

sub db_replies_id($$$) {

	my ($priv, $id, $up) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $sth;
	my $ret;

	my $emailid1;
	my $emailid2;
	if ( $up ) {
		$emailid1 = "emailid1";
		$emailid2 = "emailid2";
	} else {
		$emailid1 = "emailid2";
		$emailid2 = "emailid1";
	}

	$statement = qq(
		SELECT DISTINCT r.$emailid2, r.type
			FROM replies AS r
			JOIN emails AS e ON e.id = r.$emailid1
			WHERE r.$emailid1 = ?
			ORDER BY e.date
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref();
	} or do {
		return undef;
	};

	return undef unless $ret;

	my @reply;
	my @references;

	foreach ( @{$ret} ) {
		my $mid = ${$_}[0];
		my $type = ${$_}[1];
		if ( $type == 0 ) {
			push(@reply, $mid);
		} elsif ( $type == 1 ) {
			push(@references, $mid);
		} else {
			next;
		}
	}

	return (\@reply, \@references) if ( $up and scalar @reply != 0 );

	$statement = qq(
		SELECT e2.id
			FROM emails AS e1
			JOIN emails AS e2 ON e2.subjectid = e1.subjectid
			JOIN replies AS r ON r.$emailid2 = e2.id
			WHERE e1.id != e2.id AND r.$emailid1 != e1.id AND e1.id = ?
			ORDER BY e2.date
			LIMIT 1
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_arrayref();
	} or do {
		return (\@reply, \@references);
	};

	return (\@reply, \@references) if ( not $ret or scalar @{$ret} == 0 );

	push(@reply, ${${$ret}[0]}[0]);
	return (\@reply, \@references);

}

sub email($$) {

	my ($priv, $id) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $sth;
	my $ret;

	$statement = qq(
		SELECT messageid, list, offset
			FROM emails
			WHERE implicit = 0 AND messageid = ?
			LIMIT 1
		;
	);

	eval {
		$sth = $dbh->prepare_cached($statement);
		$sth->execute($id);
		$ret = $sth->fetchall_hashref("messageid");
	} or do {
		return undef;
	};

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

sub data($$$) {

	my ($priv, $id, $part) = @_;

	my $pemail = $priv->email($id);
	return undef unless $pemail;

	return $pemail->data($part);

}

sub delete($$) {

	my ($priv, $id) = @_;

	# TODO: add to file deleted
	# TODO: remove from database

}

1;
