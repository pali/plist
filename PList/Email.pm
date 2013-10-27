package PList::Email;

use strict;
use warnings;

sub new() {

	my %parts;
	my %headers;

	my $self = {
		parts => \%parts,
		headers => \%headers,
		datafunc => 0,
		add_datafunc => 0,
	};

	return bless $self;

}

sub part($$) {

	my ($self, $part) = @_;
	return ${$self->{parts}}{$part};

}

sub header($$) {

	my ($self, $part) = @_;
	return ${$self->{headers}}{$part};

}

sub add_part($$) {

	my ($self, $part) = @_;
	${$self->{parts}}{$part->{part}} = $part;

}

sub add_header($$) {

	my ($self, $header) = @_;
	${$self->{headers}}{$header->{part}} = $header;

}

sub set_datafunc($$) {

	my ($self, $datafunc) = @_;
	$self->{datafunc} = $datafunc;

}

sub data($$) {

	my ($self, $part) = @_;
	my $datafunc = $self->{datafunc};
	if ($datafunc) {
		return $datafunc->($part);
	}

}

sub set_add_datafunc($$) {

	my ($self, $add_datafunc) = @_;
	$self->{add_datafunc} = $add_datafunc;

}

sub add_data($$$) {

	my ($self, $part, $data) = @_;
	my $add_datafunc = $self->{add_datafunc};
	if ($add_datafunc) {
		$add_datafunc->($part, $data);
	}

}

1;
