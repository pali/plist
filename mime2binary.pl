#!/usr/bin/perl
use strict;
use warnings;

binmode STDOUT, ':utf8';

use PList::Email;
use PList::Email::MIME;
use PList::Email::Binary;

if ( @ARGV > 1 ) {
	print "To many arguments\n";
	exit 1;
}

my $str = join '', <>;
$str =~ s/^From .*\n//;

my $email = PList::Email::MIME::from_str($str);
if ( not defined $email ) {
	print "Parsing error\n";
	exit 1;
}

print PList::Email::Binary::to_str($email);
