#    PList - software for archiving and formatting emails from mailing lists
#    Copyright (C) 2014-2015  Pali Rohár <pali.rohar@gmail.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package PList::Email::Binary;

use strict;
use warnings;

use base "PList::Email";

sub lengthbytes($) {

	use bytes;
	my ($str) = @_;
	return length($str);

}

sub data($$;$) {

	my ($self, $part, $ofh) = @_;

	my $fh = $self->{fh};
	my $pemail = $self;
	my $offsets = $self->{offsets};
	my $str;

	if ( not $pemail->part($part) ) {
		return undef;
	}

	my $size = $pemail->part($part)->{size};

	my $pos = tell($fh);
	seek($fh, $self->{begin} + ${$offsets}{$part}, 0);

	if ( $ofh ) {
		my $len = 16384;
		$len = $size if $size < $len;
		while ( my $ret = read $fh, $str, $len ) {
			last if not $ret or $ret != $len;
			no warnings "utf8";
			print $ofh $str;
			$size -= $len;
			$len = $size if $size < $len;
		}
	} else {
		read $fh, $str, $size;
	}

	seek($fh, $pos, 0);

	if ( $ofh ) {
		return 1;
	} else {
		return \$str;
	}

}

sub read_email($) {

	my ($self) = @_;

	my $fh = $self->{fh};
	my $pemail = $self;
	my $offsets = $self->{offsets};

	my $line;
	my $dataoffset = 0;

	# Header is utf8 encoded
	binmode $fh, ":raw:utf8";

	my $pos = tell($fh);
	seek($fh, $self->{begin}, 0);

	$line = <$fh>;
	if ( not $line ) {
		binmode $fh, ":raw";
		return 0;
	}

	$dataoffset += lengthbytes($line);

	if ( $line ne "Parts:\n" ) {
		binmode $fh, ":raw";
		return 0;
	}

	my %parts;

	while ( $line = <$fh> ) {

		$dataoffset += lengthbytes($line);

		$line =~ s/\n//;

		if ( $line =~ /^ (\S*) (\S*) (\S*) (\S*) (\S*)(.*)$/ ) {

			my $description;
			my $filename = $6;
			if ( defined $filename ) {
				$filename =~ s/^ //;
				if ( $filename =~ /^(\S*) (.*)$/ ) {
					$filename = $1;
					$description = $2;
				}
			}
			if ( not defined $filename ) {
				$filename = "";
			}
			if ( not defined $description ) {
				$description = "";
			}

			my $part = {
				part => $1,
				size => $3,
				type => $4,
				mimetype => $5,
				filename => $filename,
				description => $description,
			};

			${$offsets}{$1} = $2;
			$pemail->add_part($part);

		} else {
			last;
		}

	}

	my $part;
	my @from;
	my @to;
	my @cc;
	my $id;
	my @reply;
	my @references;
	my $date;
	my $subject;

	my $header = {};
	my $last = "part";

	my %attrs = qw(Part: part From: from To: to Cc: cc ReplyTo: replyto Id: id Reply: reply References: references Date: date Subject: subject);
	my %scalars = qw(part 1 id 1 date 1 subject 1);

	while ( $line = <$fh> ) {

		$dataoffset += lengthbytes($line);

		$line =~ s/\n//;

		if ( $line =~ /^ (.*)$/ and $last ) {
			if ( $scalars{$last} ) {
				$header->{$last} = "$1";
			} else {
				push(@{$header->{$last}}, "$1");
			}
		} else {
			if ( $attrs{$line} ) {
				$last = $attrs{$line};
			}
			if ( $last eq "part" or $line eq "Data:" ) {
				if ( defined $header->{part} ) {
					$pemail->add_header($header);
				}
				$header = {};
			}
		}

		if ( $line eq "Data:" ) {
			last;
		}

	}

	# Turn off utf8
	binmode $fh, ":raw";

	seek($fh, $pos, 0);

	foreach ( sort keys %{$offsets} ) {
		${$offsets}{$_} += $pos + $dataoffset;
	}

	return 1;
}

sub DESTROY($) {

	my ($pemail) = @_;
	close($pemail->{fh}) if ( $pemail->{autoclose} )

}

sub from_fh($;$) {

	my ($fh, $autoclose) = @_;

	# Check if fh is seekable and if not fallback to from_str
	if ( not seek($fh, tell($fh), 0) ) {
		my $str;
		{
			local $/= undef;
			$str = <$fh>;
		}
		close($fh) if ( $autoclose );
		return from_str(\$str);
	}

	my %offsets;
	my $pemail = PList::Email::new("PList::Email::Binary");

	$pemail->{fh} = $fh;
	$pemail->{offsets} = \%offsets;
	$pemail->{autoclose} = $autoclose;
	$pemail->{begin} = tell($fh);

	if ( read_email($pemail) ) {
		return $pemail;
	} else {
		return undef;
	}

}

sub from_file($) {

	my ($filename) = @_;

	my $fh;
	if ( not open($fh, "<:mmap", $filename) ) {
		return undef;
	}

	my $pemail = from_fh($fh, 1);
	return undef unless $pemail;

	return $pemail;

}

sub from_str($) {

	my ($str) = @_;
	if ( ref $str ) {
		return from_file($str);
	} else {
		return from_file(\$str);
	}

}

sub to_fh($$) {

	my ($pemail, $fh) = @_;

	my $bin = "";
	my $offset = 0;

	my %parts = %{$pemail->parts()};
	my @partkeys = sort keys %parts;

	my %headers = %{$pemail->headers()};
	my @headerkeys = sort keys %headers;

	# Header is utf8 encoded
	binmode $fh, ":raw:utf8";

	print $fh "Parts:\n";
	foreach ( @partkeys ) {
		my $part = $parts{$_};
		print $fh " ";
		print $fh $part->{part};
		print $fh " ";
		if ( $part->{size} == 0 ) {
			print $fh "0";
		} else {
			print $fh $offset;
		}
		print $fh " ";
		print $fh $part->{size};
		print $fh " ";
		print $fh $part->{type};
		print $fh " ";
		print $fh $part->{mimetype};
		if ( $part->{filename} ) {
			print $fh " ";
			print $fh $part->{filename};
			if ( $part->{description} ) {
				print $fh " ";
				print $fh $part->{description};
			}
		}
		print $fh "\n";
		$offset += $part->{size};
	}

	foreach ( @headerkeys ) {
		my $header = $headers{$_};
		print $fh "Part:\n";
		print $fh " $header->{part}\n";
		if ( $header->{from} and @{$header->{from}} ) {
			print $fh "From:\n";
			print $fh " $_\n" foreach @{$header->{from}};
		}
		if ( $header->{to} and @{$header->{to}} ) {
			print $fh "To:\n";
			print $fh " $_\n" foreach @{$header->{to}};
		}
		if ( $header->{cc} and @{$header->{cc}} ) {
			print $fh "Cc:\n";
			print $fh " $_\n" foreach @{$header->{cc}};
		}
		if ( $header->{replyto} and @{$header->{replyto}} ) {
			print $fh "ReplyTo:\n";
			print $fh " $_\n" foreach @{$header->{replyto}};
		}
		if ( $header->{reply} and @{$header->{reply}} ) {
			print $fh "Reply:\n";
			print $fh " $_\n" foreach @{$header->{reply}};
		}
		if ( $header->{references} and @{$header->{references}} ) {
			print $fh "References:\n";
			print $fh " $_\n" foreach @{$header->{references}};
		}
		if ( $header->{id} ) {
			print $fh "Id:\n";
			print $fh " $header->{id}\n";
		}
		if ( $header->{date} ) {
			print $fh "Date:\n";
			print $fh " $header->{date}\n";
		}
		if ( $header->{subject} ) {
			print $fh "Subject:\n";
			print $fh " $header->{subject}\n";
		}
	}

	print $fh "Data:\n";

	# Data are binary raw (no utf8)
	binmode $fh, ":raw";

	foreach ( @partkeys ) {
		my $part = $parts{$_};
		if ( $part->{size} != 0 ) {
			$pemail->data($part->{part}, $fh);
		}
	}

	my $ret = tell($fh);
	$ret = 1 unless $ret;
	return $ret;

}

sub to_file($$) {

	my ($pemail, $filename) = @_;

	my $file;
	if ( not open($file, ">", $filename) ) {
		return 0;
	}

	return to_fh($pemail, $file);

}

sub to_str($) {

	my ($pemail) = @_;

	my $str;
	my $len;

	if ( $len = to_file($pemail, \$str) ) {
		return (\$str, $len);
	} else {
		return undef;
	}

}

1;
