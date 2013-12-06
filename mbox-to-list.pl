#!/usr/bin/perl

use strict;
use warnings;

use Mail::Mbox::MessageParser;

use PList::Email;
use PList::Email::MIME;
use PList::Email::Binarylist;

if ( @ARGV != 2 ) {
	print "Params: mbox list\n";
	exit 1;
}

print "MBOX file: $ARGV[0]\nList file: $ARGV[1]\n";

my $mbox = Mail::Mbox::MessageParser->new( { 'file_name' => "$ARGV[0]", 'enable_cache' => 0, 'enable_grep' => 0 } );
die unless $mbox;

my $fh;
if ( not open($fh, ">:raw", $ARGV[1]) ) {
	print "Cannot create list file $ARGV[1]\n";
	exit 1;
}

my $count = 0;

while ( ! $mbox->end_of_file() ) {

	my $email = $mbox->read_next_email();
	my $pemail = PList::Email::MIME::from_str($email);
	PList::Email::Binarylist::append_to_fh($pemail, $fh);
	++$count;
}

close($fh);

print "Written $count mails\n";
