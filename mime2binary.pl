#!/usr/bin/perl
use strict;
use warnings;

binmode STDOUT, ':utf8';

use PList::Email::MIME;

if ( @ARGV > 1 ) {
	print "To many arguments\n";
	exit 1;
}

my $str = join '', <>;
$str =~ s/^From .*\n//;

my $email = PList::Email::MIME::new_from_str($str);
if ( not defined $email ) {
	print "Parsing error\n";
	exit 1;
}

print $email->to_binary();
