package PList::List::MBox4;

use strict;
use warnings;

use base "PList::List";

use PList::Email::MIME;

use Email::Folder::Mbox;

sub new($$) {

	my ($class, $arg) = @_;

	my $is_fh = 0;
	{
		$@ = "";
		my $fd = eval { fileno $arg };
		$is_fh = !$@ && defined $fd;
	}

	my @args;

	if ( $is_fh ) {
		push(@args, "FH");
		push(@args, fh => $arg);
	} else {
		push(@args, $arg);
	}

	# NOTE: When jwz_From_ is set to 1 message separator is string "^From "
	push(@args, jwz_From_ => 1);

	# NOTE: When unescape is set to 1 every "^>+From " line is unescaped
	push(@args, unescape => 1);

	my $mbox = Email::Folder::Mbox->new(@args);
	return undef unless ref $mbox;

	return bless \$mbox, $class;

}

sub eof($) {

	my ($mbox) = @_;

	return 0 unless ${$mbox}->{_fh};
	return eof(${$mbox}->{_fh});

}

sub readnext($) {

	my ($mbox) = @_;

	my $from = ${$mbox}->next_from();
	my $message = ${$mbox}->next_messageref();
	my $messageid = ${$mbox}->messageid();

	return PList::Email::MIME::from_str($message, $from, $messageid);

}

1;
