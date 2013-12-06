#!/usr/bin/perl

use strict;
use warnings;

use PList::Email;
use PList::Email::MIME;
use PList::Email::View;

binmode STDOUT, ':utf8';

if ( @ARGV > 1 ) {
	print "To many arguments\n";
	exit 1;
}

my $str = join '', <>;
$str =~ s/^From .*\n//;

my $pemail = PList::Email::MIME::from_str($str);
if ( not defined $pemail ) {
	print "Parsing error\n";
	exit 1;
}

print PList::Email::View::to_str($pemail);
