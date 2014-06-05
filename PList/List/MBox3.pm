package PList::List::MBox3;

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
		push(@args, "_", "_fh", $arg);
	} else {
		push(@args, $arg);
	}

	my $mbox = Email::Folder::Mbox->new(@args);
	return undef unless ref $mbox;

	my $next = $mbox->next_message();
	my $nextref = \$next;
	$nextref = undef unless defined $next;

	my $priv = {
		mbox => $mbox,
		next => \$nextref,
	};

	return bless $priv, $class;

}

sub eof($) {

	my ($priv) = @_;
	if ( defined $priv->{next} ) {
		return 0;
	} else {
		return 1;
	}

}

sub readnext($) {

	my ($priv) = @_;

	my $message = $priv->{next};
	return undef unless $message;

	my $next = $priv->{mbox}->next_message();
	my $nextref = \$next;
	$nextref = undef unless defined $next;
	$priv->{next} = $nextref;

	return PList::Email::MIME::from_str($message);

}

1;
