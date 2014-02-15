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

	return bless $fh, $class;

}

sub DESTROY($) {

	my ($fh) = @_;
	close($fh);

}

sub append($$) {

	my ($fh, $pemail) = @_;

	my $str = PList::Email::Binary::to_str($pemail);
	return 0 unless $str;

	print $fh pack("V", lengthbytes($str));
	print $fh $str;

	return 1;

}

sub readnext($) {

	my ($fh) = @_;

	my $len;
	return undef unless read $fh, $len, 4;

	$len = unpack("V", $len);

	my $str;
	return undef unless read $fh, $str, $len;

	return PList::Email::Binary::from_str($str);

}

1;
