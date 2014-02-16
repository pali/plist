package PList::List::MBox;

use strict;
use warnings;

use base "PList::List";

use PList::Email::MIME;

use Mail::Mbox::MessageParser;

sub new($$) {

	my ($class, $arg) = @_;

	my $is_fh = 0;
	{
		$@ = "";
		my $fd = eval { fileno $arg };
		$is_fh = !$@ && defined $fd;
	}

	my $hash = {
		enable_cache => 0,
		enable_grep => 0,
	};

	if ( $is_fh ) {
		$hash->{file_handle} = $arg;
	} else {
		$hash->{file_name} = $arg;
	}

	my $mbox = new Mail::Mbox::MessageParser($hash);
	return undef unless ref $mbox;

	return bless \$mbox, $class;

}

sub eof($) {

	my ($mbox) = @_;
	return ${$mbox}->end_of_file();

}

sub reset($) {

	my ($mbox) = @_;
	return ${$mbox}->reset();

}

sub offset($) {

	my ($mbox) = @_;
	return ${$mbox}->offset();

}

sub skipnext($) {

	my ($mbox) = @_;

	my $email = ${$mbox}->read_next_email();
	return 0 unless $email;

	return 1;

}

sub readnext($) {

	my ($mbox) = @_;

	my $email = ${$mbox}->read_next_email();
	return undef unless $email;

	return PList::Email::MIME::from_str($email);

}

1;
