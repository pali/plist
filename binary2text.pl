#!/usr/bin/perl

use strict;
use warnings;

use Sys::Mmap;

if ( @ARGV > 1 ) {
	print "To many arguments\n";
	exit 1;
}

my $dataoffset = 0;

my $line;
my $email;

mmap($email, 0, PROT_READ, MAP_SHARED, STDIN) or die "mmap: $!";

$line = <>;
$dataoffset += length($line);

if ( $line ne "Parts:\n" ) {
	die "Parsing error";
}

my %parts;

while ( $line = <> ) {

	$dataoffset += length($line);

	$line =~ s/\n//;

	if ( $line =~ /^ ([^\s]*) ([^\s]*) ([^\s]*) ([^\s]*) ([^\s]*)(.*)$/ ) {

		my $file = $6;
		if ( $file ) {
			$file =~ s/^ //;
		} else {
			$file = "";
		}

		my $part = {
			part => $1,
			offset => $2,
			size => $3,
			type => $4,
			mimetype => $5,
			file => $file,
			header => 0,
		};

		$parts{$1} = $part;

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

while ( $line = <> ) {

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
				$parts{$header->{part}}->{header} = $header;
			}
			$header = {};
		}
	}

	if ( $line eq "Data:" ) {
		last;
	}

}

my @rootnodes = ();
my $rootnode = {
	num => 0,
	part => "0",
	nodes => \@rootnodes,
};

while (($part, $_) = each(%parts)) {

	my @path = split('/', $_->{part});
	my $root = shift(@path);

	if ( $root != 0 ) {
		print("Root: $root\n");
		die("Bad root element");
	}

	my $node = $rootnode;
	foreach (@path) {
		my $nextnode = ${$node->{nodes}}[$_];
		if ( not $nextnode ) {
			my @emptynodes = ();
			$nextnode = ${$node->{nodes}}[$_] = {
				num => $_,
				part => "",
				nodes => \@emptynodes,
			};
		}
		$node = $nextnode;
	}

	$node->{part} = $part;

}

sub printnode {

	my ($node, $alternative) = @_;

	my $partid = $node->{part};
	my $part = $parts{$partid};

	my $header = $part->{header};
	my $ret = 0;

	if ( $part->{type} eq "message" ) {

		print("=== BEGIN ===\n");

		if ( $header->{from} ) {
			print("From:");
			foreach(@{$header->{from}}) {
				$_ =~ /^([^\s]*) (.*)$/;
				print(" $2 <$1>");
			}
			print("\n");
		}

		if ( $header->{to} ) {
			print("To:");
			foreach(@{$header->{to}}) {
				$_ =~ /^([^\s]*) (.*)$/;
				print(" $2 <$1>");
			}
			print("\n");
		}

		if ( $header->{cc} ) {
			print("Cc:");
			foreach(@{$header->{cc}}) {
				$_ =~ /^([^\s]*) (.*)$/;
				print(" $2 <$1>");
			}
			print("\n");
		}

		if ( $header->{date} ) {
			print("Date: $header->{date}\n");
		}
		if ( $header->{subject} ) {
			print("Subject: $header->{subject}\n");
		}

		print("\n");

	}

	if ( $part->{type} eq "view" ) {

		if ( $part->{mimetype} eq "text/plain" ) {
			print("\n");
			print(substr($email, $dataoffset + $part->{offset}, $part->{size}));
			print("\n");
			$ret = 1;
		} else {
			print("\nType is view, but not text/plain, ignored...\n");
		}

	} elsif ( $part->{type} eq "attachment" ) {

		print("\nType is attachment, ignored...\n");

	} elsif ( $part->{type} eq "message" or $part->{type} eq "multipart" or $part->{type} eq "alternative" ) {

		my $alt;
		if ( $part->{type} eq "alternative" ) {
			$alt = 1;
		} else {
			$alt = 0;
		}

		if ( $node->{nodes} ) {
			foreach (@{$node->{nodes}}) {
				$ret = printnode($_, $alt);
				if ( $alt and $ret ) {
					last;
				}
			}
		}

	} else {

		print("\nUnknown type, ignored...\n");

	}

	if ( $part->{type} eq "message" ) {
		print("=== END ===\n");
	}

	return $ret;

}

printnode($rootnode, 0);
