package PList::List::Binary;

use strict;
use warnings;

use PList::Email;
use PList::Email::Binary;

sub lengthbytes($) {

	use bytes;
	my ($str) = @_;
	return length($str);

}

# PList::Email, fh
sub append_to_fh($$) {

	my ($pemail, $fh) = @_;

	my $str = PList::Email::Binary::to_str($pemail);
	print $fh pack("V", lengthbytes($str)) . $str;

}

# fh
sub read_next_from_fh($) {

	my ($fh) = @_;

	my $len;
	return undef unless read $fh, $len, 4;

	$len = unpack("V", $len);

	my $str;
	return undef unless read $fh, $str, $len;

	return PList::Email::Binary::from_str($str);

}

1;
