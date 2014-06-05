package PList::List::MBox2;

use strict;
use warnings;

use base "PList::List";

use PList::Email::MIME;

use Mail::Box::Mbox;

sub new($$) {

	my ($class, $filename) = @_;

	my $mbox = Mail::Box::Mbox->new(folder => $filename, access => "r", lock_type => "NONE");
	return undef unless ref $mbox;

	my $priv = {
		mbox => $mbox,
		count => $mbox->nrMessages(),
		current => 0,
	};

	return bless $priv, $class;

}

sub DESTROY($) {

	my ($priv) = @_;
	$priv->{mbox}->close(write => "NEVER");

}

sub eof($) {

	my ($priv) = @_;
	return $priv->{current} >= $priv->{count};

}

sub reset($) {

	my ($priv) = @_;
	$priv->{current} = 0;

}

sub readnext($) {

	my ($priv) = @_;

	my $message = $priv->{mbox}->message($priv->{current});
	return undef unless $message;

	$priv->{current}++;

	my $fh;
	my $str;

	open($fh, ">", \$str) or return undef;
	$message->write($fh);
	close($fh);

	$message->destruct();
	$message = undef;

	return PList::Email::MIME::from_str(\$str);

}

1;
