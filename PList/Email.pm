package PList::Email;

use strict;
use warnings;

sub new($) {

	my ($class) = @_;

	my %parts;
	my %headers;

	my $self = {
		parts => \%parts,
		headers => \%headers,
	};

	return bless $self, $class;

}

sub part($$) {

	my ($self, $part) = @_;
	return ${$self->{parts}}{$part};

}

sub parts($) {

	my ($self) = @_;
	return $self->{parts};

}

sub header($$) {

	my ($self, $part) = @_;
	return ${$self->{headers}}{$part};

}

sub headers($) {

	my ($self) = @_;
	return $self->{headers};

}

sub data($$;$) {

	die;

}

sub add_part($$) {

	my ($self, $part) = @_;
	${$self->{parts}}{$part->{part}} = $part;

}

sub add_header($$) {

	my ($self, $header) = @_;
	${$self->{headers}}{$header->{part}} = $header;

}

sub add_data($$$) {

	die;

}

1;
