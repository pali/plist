#!/usr/bin/perl
use strict;
use warnings;

use PList::Email::MIME;

binmode STDOUT, ':utf8';

open my $file, $ARGV[0] or die;

my $str = join '', <$file>;
$str =~ s/^From .*\n//;

my $email = PList::Email::MIME::new_from_str($str);
if ( not defined $email ) {
	print "Error\n";
	exit;
}
print $email->to_binary();
