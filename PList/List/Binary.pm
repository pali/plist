package PList::List::Binary;

use strict;
use warnings;

use base "PList::List";

use PList::Email;
use PList::Email::Binary;

sub lengthbytes($) {

	use bytes;
	my ($str) = @_;
	return length($str);

}

sub new($$) {

	my ($class, $filename, $readonly) = @_;

	my $mode;
	my $fh;

	if ( $readonly ) {
		$mode = "<:mmap:raw";
	} else {
		$mode = ">>:raw";
	}

	if ( not open($fh, $mode, $filename) ) {
		return undef;
	}

	my $priv = {
		fh => $fh,
		readonly => $readonly,
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

	return 0 if $priv->{readonly};

	my $fh = $priv->{fh};

	my $str = PList::Email::Binary::to_str($pemail);
	return 0 unless $str;

	print $fh pack("V", lengthbytes($str));
	print $fh $str;

	return 1;

}

sub eof($) {

	my ($priv) = @_;
	return $priv->{eof} if $priv->{eof};
	return eof($priv->{fh});

}

sub reset($) {

	my ($priv) = @_;

	return 0 unless $priv->{readonly};

	seek($priv->{fh}, 0, 0);
	$priv->{eof} = 0;

}

sub skipnext($) {

	my ($priv) = @_;

	my $fh = $priv->{fh};

	if ( $priv->{eof} or not $priv->{readonly} ) {
		return 0;
	}

	my $len;

	if ( not read($fh, $len, 4) ) {
		$priv->{eof} = 1;
		return 0;
	}

	$len = unpack("V", $len);

	if ( not seek($fh, $len, 1) ) {
		$priv->{eof} = 1;
		return 0;
	}

	return 1;

}

sub readnext($) {

	my ($priv) = @_;

	my $fh = $priv->{fh};

	if ( $priv->{eof} or not $priv->{readonly} ) {
		return undef;
	}

	my $len;
	my $str;

	if ( not read($fh, $len, 4) ) {
		$priv->{eof} = 1;
		return undef;
	}

	$len = unpack("V", $len);

	if ( not read($fh, $str, $len) ) {
		$priv->{eof} = 1;
		return undef;
	}

	return PList::Email::Binary::from_str($str);

}

1;
