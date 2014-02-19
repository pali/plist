package PList::Email::Binary;

use strict;
use warnings;

use base "PList::Email";

sub lengthbytes($) {

	use bytes;
	my ($str) = @_;
	return length($str);

}

sub data($$) {

	my ($self, $part) = @_;

	my $fh = $self->{fh};
	my $pemail = $self;
	my $offsets = $self->{offsets};

	my $str;

	my $pos = tell($fh);
	seek($fh, $self->{begin} + ${$offsets}{$part}, 0);
	read $fh, $str, $pemail->part($part)->{size};
	seek($fh, $pos, 0);

	return \$str;

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
			if ( $filename ) {
				$filename =~ s/^ //;
				if ( $filename =~ /^(\S*) (.*)$/ ) {
					$filename = $1;
					$description = $2;
				}
			}
			if ( not $filename ) {
				$filename = "";
			}
			if ( not $description ) {
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

	my %attrs = qw(Part: part From: from To: to Cc: cc Id: id Reply: reply References: references Date: date Subject: subject);
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
			local $/=undef;
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
	if (ref $str) {
		return from_file($str);
	} else {
		return from_file(\$str);
	}

}

sub to_fh($$) {

	my ($pemail, $fh) = @_;

	my $bin = "";
	my $offset = 0;

	# Header is utf8 encoded
	binmode $fh, ":raw:utf8";

	print $fh "Parts:\n";
	foreach (sort keys %{$pemail->parts()}) {
		$_ = ${$pemail->parts()}{$_};
		print $fh " ";
		print $fh $_->{part};
		print $fh " ";
		if ( $_->{size} == 0 ) {
			print $fh "0";
		} else {
			print $fh $offset;
		}
		print $fh " ";
		print $fh $_->{size};
		print $fh " ";
		print $fh $_->{type};
		print $fh " ";
		print $fh $_->{mimetype};
		if ( $_->{filename} ) {
			print $fh " ";
			print $fh $_->{filename};
			if ( $_->{description} ) {
				print $fh " ";
				print $fh $_->{description};
			}
		}
		print $fh "\n";
		$offset += $_->{size};
	}

	foreach (sort keys %{$pemail->headers()}) {
		$_ = ${$pemail->headers()}{$_};
		print $fh "Part:\n";
		print $fh " $_->{part}\n";
		if ( $_->{from} and @{$_->{from}} ) {
			print $fh "From:\n";
			print $fh " $_\n" foreach (@{$_->{from}});
		}
		if ( $_->{to} and @{$_->{to}} ) {
			print $fh "To:\n";
			print $fh " $_\n" foreach (@{$_->{to}});
		}
		if ( $_->{cc} and @{$_->{cc}} ) {
			print $fh "Cc:\n";
			print $fh " $_\n" foreach (@{$_->{cc}});
		}
		if ( $_->{reply} and @{$_->{reply}} ) {
			print $fh "Reply:\n";
			print $fh " $_\n" foreach (@{$_->{reply}});
		}
		if ( $_->{references} and @{$_->{references}} ) {
			print $fh "References:\n";
			print $fh " $_\n" foreach (@{$_->{references}});
		}
		if ( $_->{id} ) {
			print $fh "Id:\n";
			print $fh " $_->{id}\n";
		}
		if ( $_->{date} ) {
			print $fh "Date:\n";
			print $fh " $_->{date}\n";
		}
		if ( $_->{subject} ) {
			print $fh "Subject:\n";
			print $fh " $_->{subject}\n";
		}
	}

	print $fh "Data:\n";

	# Data are binary raw (no utf8)
	binmode $fh, ":raw";

	no warnings "utf8";

	foreach (sort keys %{$pemail->parts()}) {
		$_ = ${$pemail->parts()}{$_};
		if ($_->{size} != 0) {
			my $data = $pemail->data($_->{part});
			print $fh ${$data};
		}
	}

	return 1;

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
	if ( to_file($pemail, \$str) ) {
		return $str;
	} else {
		return undef;
	}

}

1;
