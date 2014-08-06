package PList::Template;

use strict;
use warnings;

use Encode qw(encode_utf8);
use HTML::Template;

sub new($$) {

	my ($class, $arg) = @_;

	my @args = (die_on_bad_params => 0, utf8 => 1, loop_context_vars => 1);

	if ( ref $arg ) {
		push(@args, scalarref => $arg);
	} else {
		push(@args, filename => $arg);
	}

	my $template = HTML::Template->new(@args);
	return bless \$template, $class;

}

sub param($$$) {

	my ($self, $param, $value) = @_;
	# NOTE: Bug in HTML::Template: Attribute ESCAPE=URL working only on encoded utf8 string. But attribute ESCAPE=HTML working on normal utf8 string
	$value = encode_utf8($value) if $param =~ /URL$/;
	return ${$self}->param($param, $value);

}

sub output($) {

	my ($self) = @_;
	return ${$self}->output();

}

1;
