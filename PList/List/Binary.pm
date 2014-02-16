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

sub new($$;$$$) {

	my ($class, $filename, $readonly, $noheader, $check) = @_;

	my $mode;
	my $fh;
	my $count;
	my $dirty;
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
			if ( $noheader ) {
				$header .= pack("V", -1);
			} else {
				$header .= pack("V", 0);
			}
			$header .= pack("V", 0) for(1..131070);
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

		my $count;
		read($fh, $count, 4);
		$count = unpack("V", $count);
		if ( $count == 4294967295 ) {
			$noheader = 1;
			$count = -1;
			$dirty = 0;
		} else {
			if ( $count > 131070 ) {
				warn "File $filename has corrupted header\n";
				close($fh);
				return undef;
			}
			if ( $noheader ) {
				$dirty = 1;
			}
		}
		if ( not $noheader ) {
			my $was_last = 0;
			for (1..131070) {
				my $off;
				if ( not read($fh, $off, 4) ) {
					warn "File $filename has small header\n";
					close($fh);
					return undef;
				}
				$off = unpack("V", $off);
				if ( $count == $_-1 and $off != 0 ) {
					warn "File $filename has corrupted header\n";
					close($fh);
					return undef;
				}
				if ( $off == 0 ) {
					$was_last = 1;
					last if ( not $check );
				} elsif ( $was_last or $off > $size ) {
					warn "File $filename has corrupted header\n";
					close($fh);
					return undef;
				}
				if ( not $was_last ) {
					push(@offsets, $off);
				}
			}

			if ( $check ) {
				my $off = tell($fh);
				if ( $off != 524288 ) {
					warn "File $filename is corrupted\n";
					close($fh);
					return undef;
				}
			}
		}

	}

	my $priv = {
		fh => $fh,
		readonly => $readonly,
		noheader => $noheader,
		dirty => $dirty,
		offsets => \@offsets,
		next => 0,
	};

	if ( $noheader ) {
		seek($fh, 524288, 0);
	}

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

	if ( $priv->{noheader} ) {

		if ( $priv->{dirty} ) {
			seek($fh, 4, 0);
			print $fh pack("V", -1);
			$priv->{dirty} = 0;
		}

		seek($fh, 0, 2);

	} else {

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

	}

	print $fh pack("V", lengthbytes($str));
	print $fh $str;

	if ( not $priv->{noheader} ) {
		push(@{$offsets}, $offset);
		seek($fh, 4, 0);
		print $fh pack("V", scalar @{$offsets});
		seek($fh, 4*(2+$num), 0);
		print $fh pack("V", $offset);
	}

	return $num;

}

sub regenerate_header($$) {

	my ($arg, $noheader) = @_;

	my $fh;

	if ( ref $arg ) {
		$fh = $arg->{fh};
	} else {
		return undef unless open($fh, "+<:raw", $arg);
	}

	my @offsets = ();

	my $pos = tell($fh);
	return undef unless seek($fh, 524288, 0);

	for (1..131070) {
		my $offset = tell($fh);
		my $len;
		last unless read($fh, $len, 4);
		$len = unpack("V", $len);
		last unless seek($fh, $len, 1);
		push(@offsets, $offset);
	}

	my $header = "list";
	$header .= pack("V", scalar @offsets);
	$header .= pack("V", $_) foreach(@offsets);

	seek($fh, 0, 0);
	print $fh $header;

	seek($fh, $pos, 0);

	if ( not $noheader and ref $arg ) {
		$arg->{noheader} = $noheader;
		$arg->{offsets} = \@offsets;
	}

	return 1;

}

sub append_to_list($$) {

	my ($filename, $pemail) = @_;

	my $fh;
	my $count;
	my $offset;
	my $len;

	my $str = PList::Email::Binary::to_str($pemail);
	return undef unless $str;

	return undef unless open($fh, "+<:raw", $filename);
	return undef unless seek($fh, 4, 0);
	return undef unless read($fh, $count, 4);

	if ( unpack("V", $count) == 4294967295 ) {
		return undef unless seek($fh, 4, 0);
		return undef unless print $fh pack("V", -1);
	}

	return undef unless seek($fh, 0, 2);
	return undef unless print $fh pack("V", lengthbytes($str));
	return undef unless print $fh $str;
	return 1;

}

sub read_from_list($$) {

	my ($filename, $num) = @_;

	my $fh;
	my $count;
	my $offset;
	my $len;
	my $str;

	return undef if $num > 131070;

	return undef unless open($fh, "<:mmap:raw", $filename);
	return undef unless seek($fh, 4, 0);
	return undef unless read($fh, $count, 4);
	$count = unpack("V", $count);

	if ( $count == 4294967295 ) {
		return undef unless seek($fh, 524288, 0);
		for (1..$num) {
			return undef unless read($fh, $len, 4);
			$len = unpack("V", $len);
			return undef unless seek($fh, $len, 1);
		}
	} else {
		return undef if $num >= $count or $count > 131070;
		return undef unless seek($fh, 4*(2+$num), 0);
		return undef unless read($fh, $offset, 4);
		$offset = unpack("V", $offset);
		return undef unless seek($fh, $offset, 0);
	}

	return undef unless read($fh, $len, 4);
	$len = unpack("V", $len);
	return undef unless read($fh, $str, $len);
	return PList::Email::Binary::from_str(\$str);

}

sub count($) {

	my ($priv) = @_;

	my $fh = $priv->{fh};

	if ( $priv->{noheader} ) {
		my $pos = tell($fh);
		return 0 unless seek($fh, 524288, 0);
		my $count = 0;
		for (1..131070) {
			my $len;
			last unless read($fh, $len, 4);
			$len = unpack("V", $len);
			last unless seek($fh, $len, 1);
			++$count;
		}
		seek($fh, $pos, 0);
		return $count;
	} else {
		return scalar @{$priv->{offsets}};
	}

}

sub eof($) {

	my ($priv) = @_;
	if ( $priv->{noheader} ) {
		return eof($priv->{fh});
	} else {
		return ( $priv->{next} >= $priv->count() );
	}

}

sub reset($) {

	my ($priv) = @_;
	if ( $priv->{noheader} ) {
		seek($priv->{fh}, 524288, 0);
	} else {
		$priv->{next} = 0;
	}

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
	my $pos;

	if ( $priv->{noheader} ) {
		$pos = tell($fh);
		return undef unless seek($fh, 524288, 0);
		for (1..$num) {
			return undef unless read($fh, $len, 4);
			$len = unpack("V", $len);
			return undef unless seek($fh, $len, 1);
		}
	} else {
		if ( not seek($fh, ${$offsets}[$num], 0) ) {
			warn "File corrupted\n";
			return undef;
		}
	}

	if ( not read($fh, $len, 4) ) {
		warn "File corrupted\n";
		seek($fh, $pos, 0) if $priv->{noheader};
		return undef;
	}

	$len = unpack("V", $len);

	if ( not read($fh, $str, $len) ) {
		warn "File corrupted\n";
		seek($fh, $pos, 0) if $priv->{noheader};
		return undef;
	}

	seek($fh, $pos, 0) if $priv->{noheader};

	return PList::Email::Binary::from_str(\$str);

}

sub readnext($) {

	my ($priv) = @_;

	return undef if $priv->eof();

	if ( not $priv->{noheader} ) {
		return $priv->readnum($priv->{next}++);
	}

	my $len;
	my $str;

	my $fh = $priv->{fh};

	if ( not read($fh, $len, 4) ) {
		warn "File corrupted\n";
		return undef;
	}

	$len = unpack("V", $len);

	if ( not read($fh, $str, $len) ) {
		warn "File corrupted\n";
		return undef;
	}

	return PList::Email::Binary::from_str(\$str);

}

1;
