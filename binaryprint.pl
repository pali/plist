#!/usr/bin/perl
use strict;
use warnings;

use Encode qw(decode_utf8);

use PList::Email;
use PList::Email::Binary;

binmode STDOUT, ':utf8';

if ( @ARGV > 1 ) {
	print "To many arguments\n";
	exit 1;
}

my $str = join '', <>;

my $pemail = PList::Email::Binary::from_str($str);
if ( not defined $pemail ) {
	print "Parsing error\n";
	exit 1;
}

foreach (sort keys %{$pemail->parts()}) {

	my $part = ${$pemail->parts()}{$_};

	my $depth = $part->{part} =~ tr/\///;
	$depth++;
	local $\ = "\n" . "| " x $depth;
	print "";
	print "=== Part: $part->{part} ===";

	if ( $part->{type} eq "message" ) {

		my $header = $pemail->header($part->{part});

#		print "=== BEGIN OF MESSAGE ===";

		if ( $header->{from} ) {
			my $str = "From:";
			foreach(@{$header->{from}}) {
				$_ =~ /^(\S*) (.*)$/;
				$str .= " $2 <$1>";
			}
			print $str;
		}

		if ( $header->{to} ) {
			my $str = "To:";
			foreach(@{$header->{to}}) {
				$_ =~ /^(\S*) (.*)$/;
				$str .= " $2 <$1>";
			}
			print $str;
		}

		if ( $header->{cc} ) {
			my $str = "Cc:";
			foreach(@{$header->{cc}}) {
				$_ =~ /^(\S*) (.*)$/;
				$str .= " $2 <$1>";
			}
			print $str;
		}

		if ( $header->{date} ) {
			print "Date: $header->{date}";
		}

		if ( $header->{subject} ) {
			print "Subject: $header->{subject}";
		}

	} elsif ( $part->{type} eq "view" ) {

		if ( $part->{mimetype} eq "text/plain" or $part->{mimetype} eq "text/plain-from-html" ) {
			# Plain text data are in utf8
			my @data = split "\n", decode_utf8($pemail->data($part->{part}));
			print $_ foreach(@data);
		} else {
			print "This is non plain text view part.";
		}

	} elsif ( $part->{type} eq "attachment" ) {

		print "Mimetype: $part->{mimetype}";
		print "Filename: $part->{filename}";
		if ( $part->{description} ) {
			print "Description: $part->{description}";
		}
		print "";
		print "This is attachment part.";

	} elsif ( $part->{type} eq "multipart" ) {

		print "This is root of multiple parts.";

	} elsif ( $part->{type} eq "alternative" ) {

		print "This is root of alternative parts.";

	} else {

		print "This is unknown part."

	}

#	undef local $\;
#	print "\n";

}

print "\n";
