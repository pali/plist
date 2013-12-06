#!/usr/bin/perl

use strict;
use warnings;

use PList::Email;
use PList::Email::Binary;
use PList::Email::Binarylist;

if ( @ARGV != 2 ) {
	print "Params: list file\n";
	exit 1;
}

my $pemail = PList::Email::Binary::from_file($ARGV[1]);
if ( not defined $pemail ) {
	print "Parsing error $ARGV[1]\n";
	exit 1;
}

my $fh;
if ( not open($fh, ">>:raw", $ARGV[0]) ) {
	print "Cannot open list file $ARGV[0]\n";
	exit 1;
}

PList::Email::Binarylist::append_to_fh($pemail, $fh);

PList::Email::Binary::done($pemail);

close($fh);
