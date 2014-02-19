package PList::Index;

use strict;
use warnings;

# directory structure:
#
# [0-9]{5}.list
# deleted
# config.pl

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

	my $priv = {
		dir => $dir,
	};

	bless $priv, $class;

}

sub DESTROY($) {

	my ($priv) = @_;

}

sub create($) {

	my ($dir) = @_;

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
