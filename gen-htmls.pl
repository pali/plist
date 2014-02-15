#!/usr/bin/perl

use strict;
use warnings;

use PList::Email;
use PList::Email::View;
use PList::Email::Binary;
use PList::List::Binary;

if ( @ARGV != 2 ) {
	print "Params: list dir\n";
	exit 1;
}

my $fh;
if ( not open($fh, "<:mmap:raw", $ARGV[0]) ) {
	print "Cannot open list file $ARGV[0]\n";
	exit 1;
}

while ($_ = PList::List::Binary::read_next_from_fh($fh)) {

	my $id = $_->header("0")->{id};
	if ( not $id ) { next; }

	my $filename = $ARGV[1] . "/$id.html";

	my $file;
	if ( not open($file, ">:raw:utf8", $filename) ) {
		print "Cannot open list file $filename\n";
		next;
	}

	print $file PList::Email::View::to_str($_);
	close($file);

	PList::Email::Binary::done($_);

}

close($fh);

