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

	if ( not $is_fh ) {
		open(my $fh, "<:mmap", $arg) or return undef;
		$arg = $fh;
	}

	binmode($arg);

	# NOTE: We need to eat first line otherwise Email::Folder::Mbox will not work with _fh key
	my $line = <$arg>;

	# HACK: We can set file handle for Email::Folder::Mbox via special key _fh and then filename will be ignored
	# NOTE: When jwz_From_ is set to 1 message separator is string "^From "
	my $mbox = Email::Folder::Mbox->new("_", _fh => $arg, jwz_From_ => 1);
	return undef unless ref $mbox;

	my $priv = {
		fh => $arg,
		mbox => $mbox,
	};

	bless $priv, $class;

	$priv->{next} = $priv->readnextref();

	return $priv;

}

sub eof($) {

	my ($priv) = @_;
	if ( defined $priv->{next} ) {
		return 0;
	} else {
		return 1;
	}

}

sub readnextref($) {

	my ($priv) = @_;

	# NOTE: Email::Folder::Mbox does not return message with header From line
	# This code will try to read previous line and later try to match From header
	my $fh = $priv->{fh};
	my $pos = tell($fh);
	my $str;
	my $seek = $pos-300;
	$seek = 0 if $seek < 0;
	seek($fh, $seek, 0);
	read($fh, $str, $pos-$seek);
	seek($fh, $pos, 0);

	my $next = $priv->{mbox}->next_message();
	return undef unless defined $next;

	if ( $str =~ /.*(From [^\n]*)\n/ ) {
		$next = $1 . "\n" . $next . "\n";
	}

	return \$next;

}

sub readnext($) {

	my ($priv) = @_;

	my $message = $priv->{next};
	return undef unless $message;

	$priv->{next} = $priv->readnextref();

	return PList::Email::MIME::from_str($message);

}

1;
