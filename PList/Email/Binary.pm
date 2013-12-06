package PList::Email::Binary;

use strict;
use warnings;

use PList::Email;

sub lengthbytes($) {

	use bytes;
	my ($str) = @_;
	return length($str);

}

sub data($$) {

	my ($private, $part) = @_;

	my $fh = $private->{fh};
	my $pemail = $private->{pemail};
	my $offsets = $private->{offsets};

	my $str;

	seek($fh, ${$offsets}{$part}, 0);
	read $fh, $str, $pemail->part($part)->{size};

	return $str;

}

sub read_email($) {

	my ($private) = @_;

	my $fh = $private->{fh};
	my $pemail = $private->{pemail};
	my $offsets = $private->{offsets};

	my $line;
	my $dataoffset = 0;

	# Header is utf8 encoded
	binmode $fh, ':raw:utf8';
	seek($fh, 0, 0);

	$line = <$fh>;
	$dataoffset += lengthbytes($line);

	if ( $line ne "Parts:\n" ) {
		binmode $fh, ':raw';
		print "read_email failed\n";
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
	binmode $fh, ':raw';

	foreach ( sort keys %{$offsets} ) {
		${$offsets}{$_} += $dataoffset;
	}

	return 1;
}

sub from_file($) {

	my ($filename) = @_;

	my $file;
	if ( not open($file, "<:raw", $filename) ) {
		return undef;
	}

	my %offsets;
	my $pemail = PList::Email::new();

	my $private = {
		fh => $file,
		pemail => $pemail,
		offsets => \%offsets,
	};

	$pemail->set_datafunc(\&data);
	$pemail->set_private($private);

	if ( read_email($private) ) {
		return $pemail;
	} else {
		close($file);
		return undef;
	}

}

sub from_str($) {

	my ($str) = @_;
	return from_file(\$str);

}

sub to_file($$) {

	my ($pemail, $filename) = @_;

	my $file;
	if ( not open($file, ">:raw:utf8", $filename) ) {
		return 0;
	}

	my $bin = "";
	my $offset = 0;

	print $file "Parts:\n";
	foreach (sort keys %{$pemail->parts()}) {
		$_ = ${$pemail->parts()}{$_};
		print $file " ";
		print $file $_->{part};
		print $file " ";
		if ( $_->{size} == 0 ) {
			print $file "0";
		} else {
			print $file $offset;
		}
		print $file " ";
		print $file $_->{size};
		print $file " ";
		print $file $_->{type};
		print $file " ";
		print $file $_->{mimetype};
		if ( defined $_->{filename} ) {
			print $file " ";
			print $file $_->{filename};
			if ( defined $_->{description} ) {
				print $file " ";
				print $file $_->{description};
			}
		}
		print $file "\n";
		$offset += $_->{size};
	}

	foreach (sort keys %{$pemail->headers()}) {
		$_ = ${$pemail->headers()}{$_};
		print $file "Part:\n";
		print $file " $_->{part}\n";
		if ( $_->{from} and @{$_->{from}} ) {
			print $file "From:\n";
			print $file " $_\n" foreach (@{$_->{from}});
		}
		if ( $_->{to} and @{$_->{to}} ) {
			print $file "To:\n";
			print $file " $_\n" foreach (@{$_->{to}});
		}
		if ( $_->{cc} and @{$_->{cc}} ) {
			print $file "Cc:\n";
			print $file " $_\n" foreach (@{$_->{cc}});
		}
		if ( $_->{reply} and @{$_->{reply}} ) {
			print $file "Reply:\n";
			print $file " $_\n" foreach (@{$_->{reply}});
		}
		if ( $_->{references} and @{$_->{references}} ) {
			print $file "References:\n";
			print $file " $_\n" foreach (@{$_->{references}});
		}
		if ( $_->{id} ) {
			print $file "Id:\n";
			print $file " $_->{id}\n";
		}
		if ( $_->{date} ) {
			print $file "Date:\n";
			print $file " $_->{date}\n";
		}
		if ( $_->{subject} ) {
			print $file "Subject:\n";
			print $file " $_->{subject}\n";
		}
	}

	print $file "Data:\n";

	# Data are binary raw (no utf8)
	binmode $file, ":raw";

	no warnings 'utf8';

	foreach (sort keys %{$pemail->parts()}) {
		$_ = ${$pemail->parts()}{$_};
		if ($_->{size} != 0) {
			print $file $pemail->data($_->{part});
		}
	}

	close($file);
	return 1;

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
