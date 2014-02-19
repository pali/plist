package PList::Index;

use strict;
use warnings;

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

	close($fh);

	my $dbh = DBI->connect($datasource, $username, $password, { RaiseError => 1, AutoCommit => 0 });
	if ( not $dbh ) {
		warn $DBI::errstr;
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

sub create($$$$) {

	my ($dir, $datasource, $username, $password) = @_;

	if ( not make_path($dir) ) {
		warn "Cannot create dir $dir\n";
		return 0;
	}

	my $dbh = DBI->connect($datasource, $username, $password, { RaiseError => 1 });
	if ( not $dbh ) {
		warn $DBI::errstr;
		return 0;
	}

	my $statement = qq(
		CREATE TABLE subjects (
			id		INTEGER PRIMARY KEY NOT NULL,
			subject		TEXT UNIQUE
		);
		CREATE TABLE emails (
			id		INTEGER PRIMARY KEY NOT NULL,
			messageid	TEXT UNIQUE NOT NULL,
			date		INTEGER,
			subjectid	INTEGER NOT NULL,
			list		TEXT NOT NULL,
			offset		INTEGER,
			FOREIGN KEY(subjectid) REFERENCES subjects(id)
		);
		CREATE TABLE references (
			id		INTEGER PRIMARY KEY NOT NULL,
			emailid1	INTEGER NOT NULL,
			emailid2	INTEGER NOT NULL,
			type		INTEGER,
			FOREIGN KEY(emailid1) REFERENCES emails(id),
			FOREIGN KEY(emailid2) REFERENCES emails(id)
		);
		CREATE TABLE subreferences (
			id		INTEGER PRIMARY KEY NOT NULL,
			subjectid	INTEGER NOT NULL,
			emailid		INTEGER NOT NULL,
			FOREIGN KEY(subjectid) REFERENCES subjects(id),
			FOREIGN KEY(emailid) REFERENCES emails(id)
		);
		CREATE TABLE address (
			id		INTEGER PRIMARY KEY NOT NULL,
			email		TEXT NOT NULL,
			name		TEXT NOT NULL
		);
		CREATE TABLE addressess (
			id		INTEGER PRIMARY KEY NOT NULL,
			emailid		INTEGER NOT NULL,
			addressid	INTEGER NOT NULL,
			type		INTEGER,
			FOREIGN KEY(emailid) REFERENCES emails(id),
			FOREIGN KEY(addressid) REFERENCES address(id)
		);
	);

	my $ret = $dbh->do($statement);
	$dbh->disconnect();

	if ( $ret < 0 ) {
		warn $DBI::errstr;
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

sub add_list($$) {

	my ($priv, $list) = @_;

}

sub add_email($$) {

	my ($priv, $pemail) = @_;

}

sub db_email($$) {

	my ($priv, $id) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
	my $email = { from => [], to => [], cc => [] };
	my $ret;

	$statement = qq(
		SELECT e.id, e.messageid, e.date, s.subject, e.list, e.offset
			FROM emails AS e
			JOIN subjects AS s ON s.id = e.subjectid
			WHERE e.messageid = ?
			LIMIT 1
		;
	);

	$dbh->prepare_cached($statement);
	$dbh->execute($id);
	$ret = $dbh->fetchall_hashref("id");

	return undef unless $ret and $ret->{$id};

	$email->{$_} = $ret->{$id}->{$_} foreach (keys %{$ret->{$id}});

	$statement = qq(
		SELECT DISTINCT a.email, a.name, s.type
			FROM addressess AS s
			JOIN address AS a ON a.id = s.addressid
			WHERE emailid = ?
		;
	);

	$dbh->prepare_cached($statement);
	$dbh->execute($email->{id});
	$ret = $dbh->fetchall_arrayref();

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
		push(@{$array}, {email => $_->[0], name => $_->[1]});
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
		$args{subject} =~ s/^\s*[\s*RE\s*:\s*]\s*//i;
		$args{subject} =~ s/^\s*[\s*FWD\s*:\s*]\s*//i;
		$args{subject} =~ s/^\s*//;
		$args{subject} =~ s/\s*$//;
	}

	$statement = "SELECT DISTINCT e.messageid FROM emails AS e";

	if ( exists $args{subject} ) {
		$statement .= " JOIN subjects AS s ON s.id = e.subjectid";
	}

	if ( exists $args{from_email} or exists $args{from_name} or exists $args{to_email} or exists $args{to_name} or exists $args{cc_email} or exists $args{cc_name} ) {
		$statement .= " JOIN addressess AS s ON s.emailid = e.id JOIN address AS a ON a.id = s.addressid";
	}

	if ( exists $args{date1} or exists $args{date2} or exists $args{subject} or exists $args{from_email} or exists $args{from_name} or exists $args{to_email} or exists $args{to_name} or exists $args{cc_email} or exists $args{cc_name} ) {
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

	# TODO: from, to, cc
#	if ( exists $args{from_email} ) {
#		$statement .= " a.email LIKE %?% AND ...";
#	}

	$statement =~ s/AND$//;

	$dbh->prepare_cached($statement);
	$dbh->execute(@args);
	$ret = $dbh->fetchall_arrayref();

	return undef unless $ret;
	return map { ${$_}[0] } @{$ret};

}

sub db_references($$$) {

	my ($priv, $id, $up) = @_;

	my $dbh = $priv->{dbh};

	my $statement;
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
		SELECT DISTINCT e2.messageid, r.type
			FROM emails AS e1
			JOIN references AS r ON r.$emailid1 = e1.id
			JOIN emails AS e2 ON e2.id = r.$emailid2
			WHERE e1.messageid = ?
		;
	);

	$dbh->prepare_cached($statement);
	$dbh->execute($id);
	$ret = $dbh->fetchall_arrayref();

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
			JOIN references AS r ON e2.messageid
			WHERE e1.messageid = ? AND e1.messageid != e2.messageid AND r.$emailid1 != e1.id
			ORDER BY e2.date
			LIMIT 1
		;
	);

	$dbh->prepare_cached($statement);
	$dbh->execute($id);
	$ret = $dbh->fetchall_arrayref();

	return (\@reply, \@references) if ( not $ret or scalar @{$ret} == 0 );

	push(@reply, ${@{$ret}}[0]);
	return (\@reply, \@references);

}

sub email($$) {

	my ($priv, $id) = @_;

}

sub view($$$) {

	my ($priv, $id, $part) = @_;

}

sub data($$$) {

	my ($priv, $id, $part) = @_;

}

sub delete_mark($$) {

	my ($priv, $id) = @_;

}

sub delete_unmark($$) {

	my ($priv, $id) = @_;

}

1;
