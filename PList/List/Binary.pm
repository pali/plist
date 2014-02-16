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

sub new($$$) {

	my ($class, $filename, $readonly) = @_;

	my $mode;
	my $fh;
	my @offsets = ();

	if ( $readonly ) {
		$mode = "<:mmap:raw";
	} else {
		$mode = "+<:raw";
	}

	my $ret = open($fh, $mode, $filename);

	if ( not $ret ) {

		if ( $readonly ) {
			warn "Cannot open file $filename: $!\n";
			return undef;
		} else {
			$ret = open($fh, "+>:raw", $filename);
			if ( not $ret ) {
				warn "Cannot create file $filename: $!\n";
				return undef;
			}
			my $header = "list";
			$header .= pack("V", 0) for(1..131071);
			print $fh $header;
		}

	} else {

		if ( not seek($fh, 0, 2) ) {
			warn "File $filename is not seekable: $!\n";
			close($fh);
			return undef;
		}

		my $size = tell($fh);
		if ( not $size ) {
			warn "File $filename is not seekable: $!\n";
			close($fh);
			return undef;
		}

		seek($fh, 0, 0);

		my $sig;
		read($fh, $sig, 4);
		if ( $sig ne "list" ) {
			warn "File $filename does not have header signature\n";
			close($fh);
			return undef;
		}

		my $was_last = 0;
		for (1..131071) {
			my $off;
			if ( not read($fh, $off, 4) ) {
				warn "File $filename has small header\n";
				close($fh);
				return undef;
			}
			$off = unpack("V", $off);
			if ( $off == 0 ) {
				$was_last = 1;
			} elsif ( $off > $size ) {
				warn "File $filename has corrupted header\n";
				close($fh);
				return undef;
			}
			if ( not $was_last ) {
				push(@offsets, $off);
			}
		}

		my $off = tell($fh);
		if ( $off != 524288 ) {
			warn "File $filename is corrupted\n";
			close($fh);
			return undef;
		}

	}

	my $priv = {
		fh => $fh,
		readonly => $readonly,
		offsets => \@offsets,
		next => 0,
	};

	return bless $priv, $class;

}

sub DESTROY($) {

	my ($priv) = @_;
	close($priv->{fh});

}

sub append($$) {

	my ($priv, $pemail) = @_;

	if ( $priv->{readonly} ) {
		warn "File is readonly\n";
		return undef;
	}

	my $fh = $priv->{fh};
	my $offsets = $priv->{offsets};

	my $str = PList::Email::Binary::to_str($pemail);
	if ( not $str ) {
		warn "Cannot read email\n";
		return undef;
	}

	my $num = scalar @{$offsets};
	my $offset;

	if ( $num != 0 ) {

		$offset = ${$offsets}[$num-1];

		if ( not seek($fh, $offset, 0) ) {
			warn "File is corrupted\n";
			return undef;
		}

		my $len;
		if ( not read($fh, $len, 4) ) {
			warn "File is corrupted\n";
			return undef;
		}

		$offset += 4 + unpack("V", $len);

	} else {

		$offset = 524288;

	}

	seek($fh, 0, 2);
	if ( tell($fh) != $offset ) {
		warn "File is corrupted\n";
		return undef;
	}

	print $fh pack("V", lengthbytes($str));
	print $fh $str;

	push(@{$offsets}, $offset);
	seek($fh, 4*(1+$num), 0);
	print $fh pack("V", $offset);

	return $num;

}

sub count($) {

	my ($priv) = @_;
	return scalar @{$priv->{offsets}};

}

sub eof($) {

	my ($priv) = @_;
	return ( $priv->{next} >= $priv->count() );

}

sub reset($) {

	my ($priv) = @_;
	$priv->{next} = 0;

}

sub readnum($$) {

	my ($priv, $num) = @_;

	my $fh = $priv->{fh};
	my $offsets = $priv->{offsets};

	if ( $num >= $priv->count() ) {
		return undef;
	}

	my $len;
	my $str;

	if ( not seek($fh, ${$offsets}[$num], 0) ) {
		warn "File corrupted\n";
		return undef;
	}

	if ( not read($fh, $len, 4) ) {
		warn "File corrupted\n";
		return undef;
	}

	$len = unpack("V", $len);

	if ( not read($fh, $str, $len) ) {
		warn "File corrupted\n";
		return undef;
	}

	return PList::Email::Binary::from_str($str);

}

sub readnext($) {

	my ($priv) = @_;
	return undef if $priv->eof();
	return $priv->readnum($priv->{next}++);

}

1;
