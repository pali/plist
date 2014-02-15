#!/usr/bin/perl

use strict;
use warnings;

use PList::Email;
use PList::Email::MIME;
use PList::Email::Binary;

use PList::Email::View;

use PList::Threads::Binary;

use PList::List;
use PList::List::Binary;

sub help() {

	print "help:\n";
	print "list view <list>\n";
	print "list add-mbox <list> <mbox>\n";
	print "list add-bin <list> <bin>\n";
	print "list get-bin <list> <num> [<bin>]\n";
	print "list get-part <list> <num> <part> [<file>]\n";
	print "list gen-html <list> <num> [<html>]\n";
	print "list gen-txt <list> <num> [<txt>]\n";
	print "bin view [<bin>]\n";
	print "bin from-mime [<mime>] [<bin>]\n";
	print "bin get-part <part> [<bin>] [<file>]\n";
	print "bin gen-html [<bin>] [<html>]\n";
	print "bin gen-txt [<bin>] [<txt>]\n";
	exit 1;

}

sub open_mbox($) {

	my ($filename) = @_;
	my $list = new PList::List::MBox($filename);
	die "Cannot open mbox file $filename\n" unless $list;
	return $list;

}

sub open_list($$) {

	my ($filename, $readonly) = @_;
	my $list = new PList::List::Binary($filename, $readonly);
	die "Cannot open list file $filename\n" unless $list;
	return $list;

}

sub open_bin($) {

	my ($filename) = @_;
	my $pemail;
	if ( $filename ) {
		$pemail = PList::Email::Binary::from_file($filename);
	} else {
		binmode STDIN, ":raw:utf8";
		my $str = join "", <STDIN>;
		$pemail = PList::Email::Binary::from_str($str);
	}
	die "Cannot open bin file $filename\n" unless $pemail;
	return $pemail;

}

sub open_input($$) {

	my ($filename, $mode) = @_;
	my $fh;
	if ( $filename ) {
		if ( not open($fh, "<:mmap" . $mode, $filename) ) {
			die "Cannot open input file $filename\n";
		}
	} else {
		$fh = *STDIN;
		binmode $fh, $mode;
	}
	return $fh;

}

sub open_output($$) {

	my ($filename, $mode) = @_;
	my $fh;
	if ( $filename ) {
		if ( not open($fh, ">" . $mode, $filename) ) {
			die "Cannot open output file $filename\n";
		}
	} else {
		$fh = *STDOUT;
		binmode $fh, $mode;
	}
	return $fh;

}

sub bin_view($) {

	my ($pemail) = @_;

	my $header = $pemail->header("0");
	if ( not $header ) {
		print "Error: Corrupted header\n";
		return;
	}

	print "Id: " .$header->{id} . "\n";

	if ( $header->{from} and @{$header->{from}} ) {
		print "From:";
		foreach (@{$header->{from}}) {
			$_ =~ /^(\S*)/;
			print " " . $1;
		}
		print "\n";
	}

	if ( $header->{to} and @{$header->{to}} ) {
		print "To:";
		foreach (@{$header->{to}}) {
			$_ =~ /^(\S*)/;
			print " " . $1;
		}
		print "\n";
	}

	if ( $header->{cc} and @{$header->{cc}} ) {
		print "Cc:";
		foreach (@{$header->{cc}}) {
			$_ =~ /^(\S*)/;
			print " " . $1;
		}
		print "\n";
	}

	if ( $header->{subject} ) {
		print "Subject: " . $header->{subject} . "\n";
	}

	print "Parts:";
	print " " . $_ foreach sort keys %{$pemail->parts()};
	print "\n";

}

sub bin_get($$$) {

	my ($listfile, $binfile, $num) = @_;

	my $fh = open_output($binfile, ":raw");
	my $list = open_list($listfile, 1);

	my $count = 0;
	$list->skipnext() while ( not $list->eof() and $count++ != $num );

	die "Cannot find email (num $num) in list file $listfile (max $count)\n" unless $count == $num or not $list->eof();

	my $pemail = $list->readnext();
	die "Cannot read email (num $num) from list file $listfile\n" unless $pemail;

	return ($pemail, $fh);

}


my $mod = shift @ARGV;
my $command = shift @ARGV;

if ( not $mod or not $command ) {

	help();

} elsif ( $mod eq "list" ) {

	my $listfile = shift @ARGV;
	help() unless $listfile;

	if ( $command eq "view" ) {

		my $list = open_list($listfile, 1);

		my $count = 0;
		while ( not $list->eof() ) {
			$list->skipnext();
			++$count;
		}

		binmode STDOUT, ":utf8";

		print "Total emails in list: $count\n\n";

		$list->reset();
		$count = 0;
		while ( not $list->eof() ) {
			my $pemail = $list->readnext();
			print "Number: $count\n";
			if (not $pemail) {
				print "Error: Corrupted email\n\n";
				++$count;
				next;
			}
			bin_view($pemail);
			print "\n";
			++$count;
		}

	} elsif ( $command eq "add-mbox" ) {

		my $mboxfile = shift @ARGV;
		help() unless $mboxfile;

		my $mbox = open_mbox($mboxfile);
		my $list = open_list($listfile, 0);

		my $count = 0;
		my $success = 0;

		while ( not $mbox->eof() ) {

			++$count;

			my $pemail = $mbox->readnext();
			if ( not $pemail ) {
				warn "Cannot read email from mbox file $mboxfile ($count)\n";
				next;
			}

			if ( not $list->append($pemail) ) {
				warn "Cannot write email to list file $listfile ($count)\n";
				next;
			}

			++$success;

		}

		print "Written $success (/$count) emails from mbox file $mboxfile to list file $listfile\n";

	} elsif ( $command eq "add-bin" ) {

		my $binfile = shift @ARGV;
		help() unless $binfile;

		my $pemail = open_bin($binfile);
		my $list = open_list($listfile, 0);

		$_ = $list->append($pemail);
		die "Cannot write email from bin file $binfile to list file $listfile\n" unless $_;

		print "Written one email from bin file $binfile to list file $listfile\n";

	} elsif ( $command eq "get-bin" ) {

		my $num = shift @ARGV;
		help() unless defined $num;

		my $file = shift @ARGV;

		my ($pemail, $fh) = bin_get($listfile, $file, $num);
		PList::Email::Binary::to_fh($pemail, $fh);

	} elsif ( $command eq "get-part" ) {

		my $num = shift @ARGV;
		help() unless defined $num;

		my $part = shift @ARGV;
		help() unless $part;

		my $file = shift @ARGV;

		my ($pemail, $fh) = bin_get($listfile, $file, $num);

		my $data = $pemail->data($part);
		die "Cannot read part $part from email (num $num) from list file $listfile\n" unless $data;

		print $fh $data;

	} elsif ( $command eq "gen-html" or $command eq "gen-txt" ) {

		my $num = shift @ARGV;
		help() unless defined $num;

		my $file = shift @ARGV;

		my ($pemail, $fh) = bin_get($listfile, $file, $num);

		binmode $fh, ":raw:utf8";

		my %args;
		$args{html_output} = 0 if ( $command eq "gen-txt" );

		my $output = PList::Email::View::to_str($pemail, %args);
		die "Cannot generate output\n" unless $output;

		print $fh $output;

	} else {

		help();

	}

} elsif ( $mod eq "bin" ) {

	if ( $command eq "view" ) {

		my $binfile = shift @ARGV;
		my $pemail = open_bin($binfile);
		bin_view($pemail);

	} elsif ( $command eq "from-mime" ) {

		my $mimefile = shift @ARGV;
		my $binfile = shift @ARGV;

		my $input = open_input($mimefile, ":raw:utf8");
		my $output = open_output($binfile, ":raw:utf8");

		my $str = join "", <$input>;
		$str =~ s/^From .*\n//;

		my $pemail = PList::Email::MIME::from_str($str);
		die "Cannot read email\n" unless $pemail;

		$str = PList::Email::Binary::to_str($pemail);
		die "Cannot parse email\n" unless $str;

		print $output $str;

	} elsif ( $command eq "get-part" ) {

		my $part = shift @ARGV;
		help() unless $part;

		my $binfile = shift @ARGV;
		my $file = shift @ARGV;

		my $pemail = open_bin($binfile);
		my $output = open_output($file, ":raw:utf8");

		my $data = $pemail->data($part);
		die "Cannot read part $part from email bin file $binfile\n" unless $data;

		print $output ${$data};

	} elsif ( $command eq "gen-html" or $command eq "gen-txt" ) {

		my $binfile = shift @ARGV;
		my $file = shift @ARGV;

		my $pemail = open_bin($binfile);
		my $output = open_output($file, ":raw:utf8");

		my %args;
		$args{html_output} = 0 if ( $command eq "gen-txt" );

		my $str = PList::Email::View::to_str($pemail, %args);
		die "Cannot generate output\n" unless $str;

		print $output $str;

	} else {

		help();

	}

} else {

	help();

}
