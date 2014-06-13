package PList::List::Binary;

use strict;
use warnings;

use base "PList::List";

use PList::Email;
use PList::Email::Binary;

sub new($$;$) {

	my ($class, $filename, $append) = @_;

	my $mode;
	my $fh;

	if ( $append ) {
		$mode = ">>:raw";
	} else {
		$mode = "<:mmap:raw";
	}

	if ( not open($fh, $mode, $filename) ) {
		return undef;
	}

	if ( $append and not flock($fh, 2) ) {
		warn "Cannot lock list file for appending\n";
		close($fh);
		return undef;
	}

	my $priv = {
		fh => $fh,
		append => $append,
		eof => 0,
	};

	return bless $priv, $class;

}

sub DESTROY($) {

	my ($priv) = @_;
	close($priv->{fh});

}

sub append($$) {

	my ($priv, $pemail) = @_;

	return undef unless $priv->{append};

	my $fh = $priv->{fh};

	my ($str, $len) = PList::Email::Binary::to_str($pemail);
	return undef unless $str;

	my $pos = tell($fh);

	print $fh pack("V", $len);
	print $fh ${$str};

	return $pos;

}

sub readat($$) {

	my ($priv, $offset) = @_;

	return undef if $priv->{append};

	return undef unless seek($priv->{fh}, $offset, 0);

	$priv->{eof} = 0;

	return $priv->readnext();

}

sub readnext($) {

	my ($priv) = @_;

	my $fh = $priv->{fh};

	return undef if $priv->{eof} or $priv->{append};

	my $len;
	my $str;

	if ( read($fh, $len, 4) != 4 ) {
		$priv->{eof} = 1;
		return undef;
	}

	$len = unpack("V", $len);

	if ( read($fh, $str, $len) != $len ) {
		$priv->{eof} = 1;
		return undef;
	}

	return PList::Email::Binary::from_str($str);

}

sub offset($) {

	my ($priv) = @_;
	return tell($priv->{fh});

}

sub eof($) {

	my ($priv) = @_;
	return 1 if $priv->{eof};
	return eof($priv->{fh});

}

sub reset($) {

	my ($priv) = @_;

	return if $priv->{append};

	seek($priv->{fh}, 0, 0);
	$priv->{eof} = 0;

}

1;
