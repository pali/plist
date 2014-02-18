package PList::Index;

use strict;
use warnings;

use File::Copy;

# OLD!!!
# structure:
# imported_[0-9]{5}.mbox
# [0-9]{5}.mbox
# imported_[0-9]{5}.list
# [0-9]{5}.list
# [0-9]{5}.offs
# threads
# mark_deleted.txt

# NEW:
# [0-9]{5}.list
# threads
# deleted

sub new($$;$) {

	my ($class, $dir, $create) = @_;

	if ( $create ) {
		die "Cannot create directory $dir" unless mkpath($dir);
	}

	my $priv = {
		dir => $dir,
	};

	bless $priv, $class;

}

sub DESTROY($) {

}

# file functions

# priv, mbox
#sub add_mbox($$) {
#
#	my ($priv, $mbox) = @_;
#
#	my $dh;
#	return undef unless opendir($dh, $priv->{dir});
#	my @imported = sort grep { /^imported_[0-9]{5}.mbox$/ } readdir $dh;
#	my $last = $imported[-1];
#	$last =~ s/^imported_([0-9]{5}).mbox$/$1/;
#	$last = sprintf("%05d", $last+1);
#
#	copy($mbox, $priv->{dir} . "/imported_" . $last . ".mbox");
#
#}

# priv, pemail
sub add_email($$) {

	my ($priv, $pemail) = @_;

}

# priv, $id, $up, $file, $offset
sub add_threads($$) {

}

# recovery functions

sub regenerate_lists_headers($) {

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

sub email($$) {

}

# priv, id, config
sub view($$;%) {

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
