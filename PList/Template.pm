package PList::Template;

use strict;
use warnings;

use base "HTML::Template";

sub new($$) {

	my ($class, $arg) = @_;

	my @args = (die_on_bad_params => 0, utf8 => 1);

	if ( ref $arg ) {
		push(@args, scalarref => $arg);
	} else {
		push(@args, filename => $arg);
	}

	return $class->SUPER::new(@args);

}

1;
