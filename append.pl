#!/usr/bin/perl

use strict;
use warnings;

use PList::Email;
use PList::Email::Binary;
use PList::List::Binary;

if ( @ARGV != 2 ) {
	print "Params: list file\n";
	exit 1;
}

my $pemail = PList::Email::Binary::from_file($ARGV[1]);
if ( not defined $pemail ) {
	print "Parsing error $ARGV[1]\n";
	exit 1;
}

my $list = new PList::List::Binary($ARGV[0], 0);
if ( not defined $list ) {
	print "Cannot open list file $ARGV[0]\n";
	exit 1;
}

if ( not $list->append($pemail) ) {
	print "Cannot append email to list file\n";
	exit 1;
}
