package PList::Index;

use strict;
use warnings;

sub new($$) {

	my ($class, $dir) = @_;

	my $priv = {};

	bless $priv, $class;

}

sub DESTROY($) {

}

# file functions

sub add_mbox($$) {

}

sub add_bin($$) {

}

sub add_threads($$) {

}

# recovery functions

sub regenerate_lists($) {

}

sub regenerate_threads($) {

}

# import functions

sub import_mime($$) {

}

sub import_mbox($$) {

}

# priv, id
sub delete_mark($$) {

}

sub delete_unmark($$) {

}

# threads functions

sub roots($) {

}

sub up($) {

}

sub down($) {

}

# data functions

# priv, id, config
sub view($$$) {

}

# priv, id, part
sub data($$$) {

}

# priv, id
sub parts($$) {

}

# priv, id, part
sub headers($$$) {

}

1;
