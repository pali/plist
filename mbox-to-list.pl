#!/usr/bin/perl

use strict;
use warnings;

use Mail::Mbox::MessageParser;

use PList::Email;
use PList::Email::MIME;
use PList::List::Binary;

if ( @ARGV != 2 ) {
	print "Params: mbox list\n";
	exit 1;
}

print "MBOX file: $ARGV[0]\nList file: $ARGV[1]\n";

my $mbox = Mail::Mbox::MessageParser->new( { 'file_name' => "$ARGV[0]", 'enable_cache' => 0, 'enable_grep' => 0 } );
die unless $mbox;

my $list = new PList::List::Binary($ARGV[1], 0);
if ( not $list ) {
	print "Cannot create list file $ARGV[1]\n";
	exit 1;
}

my $count = 0;

while ( ! $mbox->end_of_file() ) {

	my $email = $mbox->read_next_email();
	my $pemail = PList::Email::MIME::from_str($email);
	if (not $pemail) {
		print "Cannot parse MIME email\n";
		next;
	}
	if (not $list->append($pemail)) {
		print "Cannot append email to list\n";
		next;
	}
	++$count;
}

print "Written $count mails\n";
