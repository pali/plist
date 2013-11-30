package PList::Email::Binary;

use strict;
use warnings;

use PList::Email;

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
	my $dataoffset;

	seek($fh, 0, 0);

	$line = <$fh>;
	$dataoffset += length($line);

	if ( $line ne "Parts:\n" ) {
		print "read_email failed\n";
		return 0;
	}

	my %parts;

	while ( $line = <$fh> ) {

		$dataoffset += length($line);

		$line =~ s/\n//;

		if ( $line =~ /^ ([^\s]*) ([^\s]*) ([^\s]*) ([^\s]*) ([^\s]*)(.*)$/ ) {

			my $description;
			my $filename = $6;
			if ( $filename ) {
				$filename =~ s/^ //;
				if ( $filename =~ /^([^\s]*) (.*)$/ ) {
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

		$dataoffset += length($line);

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

	foreach ( keys ${$offsets} ) {
		${$offsets}{$_} += $dataoffset;
	}
}

sub from_fh($) {

	my ($fh) = @_;
	my %offsets;

	my $pemail = PList::Email::new();

	my $private = {
		fh => $fh,
		pemail => $pemail,
		offsets => \%offsets,
	};

	$pemail->set_datafunc(\&data);
	$pemail->set_private(\$private);

	if ( read_email($private) ) {
		return $pemail;
	} else {
		return undef;
	}

}

sub from_file($) {

	my ($filename) = @_;

	my $file;
	if ( not open($file, "<:raw", $filename) ) {
		return undef;
	}

	return from_fh($file);

}

sub from_str($) {

	my ($str) = @_;

	my $fh;
	if ( not open($fh, "<:raw", \$str) ) {
		return undef;
	}

	return from_fh($fh);

}

sub write_email($$) {

	my ($pemail, $fh) = @_;

	my $bin = "";
	my $offset = 0;

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
		if ( defined $_->{filename} ) {
			print $fh " ";
			print $fh $_->{filename};
			if ( defined $_->{description} ) {
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
		if ( @{$_->{from}} ) {
			print $fh "From:\n";
			print $fh " $_\n" foreach (@{$_->{from}});
		}
		if ( @{$_->{to}} ) {
			print $fh "To:\n";
			print $fh " $_\n" foreach (@{$_->{to}});
		}
		if ( @{$_->{cc}} ) {
			print $fh "Cc:\n";
			print $fh " $_\n" foreach (@{$_->{cc}});
		}
		if ( @{$_->{reply}} ) {
			print $fh "Reply:\n";
			print $fh " $_\n" foreach (@{$_->{reply}});
		}
		if ( @{$_->{references}} ) {
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
	foreach (sort keys %{$pemail->parts()}) {
		$_ = ${$pemail->parts()}{$_};
		if ($_->{size} != 0) {
			print $fh $pemail->data($_->{part});
		}
	}

}

sub to_str($) {

	my ($pemail) = @_;

	my $str;
	my $fh;
	if ( not open($fh, ">:raw", \$str) ) {
		return undef;
	}

	write_email($pemail, $fh);
	close($fh);

	return $str;

}

sub to_file($$) {

	my ($pemail, $filename) = @_;

	my $file;
	if ( not open($file, ">:raw", $filename) ) {
		return 0;
	}

	write_email($pemail, $file);
	close($file);

	return 1;

}

1;
