package PList::Threads::Binary;

use strict;
use warnings;

use base "PList::Threads";

use Storable;

sub new($$) {

	my ($class, $file) = @_;

	my $priv = {
		file => $file,
		emails => {},
		roots => {},
	};

	eval {
		my $hash = retrieve($file);
		$priv->{emails} = $hash->{emails};
		$priv->{roots} = $hash->{roots};
	};

	bless $priv, $class;

}

sub save($) {

	my ($priv) = @_;

	my $hash = {
		emails => $priv->{emails},
		roots => $priv->{roots},
	};

	my $ret = 0;

	eval {
		store($hash, $priv->{file});
		$ret = 1;
	};

	return $ret;

}

sub add_email($$$$$) {

	my ($priv, $id, $up, $file, $offset) = @_;

	my $emails = $priv->{emails};
	my $roots = $priv->{roots};

	if ( $emails->{$id} ) {

		# Email with ID is already there
		if ( $emails->{$id}->{file} ) {
			return;
		}

		# Email with ID is not there, but other emails reference it
		my $email = $emails->{$id};
		$email->{up} = $up;
		$email->{file} = $file;
		$email->{offset} = $offset;

		return;

	}

	my $email = {
		up => $up,
		down => [],
		file => $file,
		offset => $offset,
	};

	$emails->{$id} = $email;

	if ( ref $up ) {
		foreach(@{$up}) {
			if ( $emails->{$_} ) {
				push(@{$emails->{$_}->{down}}, $id);
			} else {
				$emails->{$_} = {
					up => undef,
					down => [$id],
					file => undef,
					offset => 0,
				};
			}
		}
	} else {
		if ( $emails->{$up} ) {
			push(@{$emails->{$up}->{down}}, $id);
		} else {
			$emails->{$up} = {
				up => undef,
				down => [$id],
				file => undef,
				offset => 0,
			};
		}
	}

	if ( not $up ) {
		$roots->{$id} = 1;
	}

}

sub del_email($$) {

	my ($priv, $id) = @_;

	my $emails = $priv->{emails};
	my $roots = $priv->{roots};

	if ( not $emails->{$id} ) {
		return;
	}

	if ( $roots->{$id} ) {
		delete $roots->{$id};
	}

	if ( scalar @{$emails->{$id}->{down}} > 0 ) {
		my $email = $emails->{$id};
		$email->{up} = undef;
		$email->{file} = undef;
		$email->{offset} = 0;
	} else {
		delete $emails->{$id};
	}

}

sub roots($) {

	my ($priv) = @_;
	return $priv->{roots};

}

sub up($$) {

	my ($priv, $id) = @_;
	return $priv->{emails}->{$id}->{up};

}

sub down($$) {

	my ($priv, $id) = @_;
	return $priv->{emails}->{$id}->{down};

}

sub file($$) {

	my ($priv, $id) = @_;
	return $priv->{emails}->{$id}->{file};

}

sub offset($$) {

	my ($priv, $id) = @_;
	return $priv->{emails}->{$id}->{offset};

}

1;
