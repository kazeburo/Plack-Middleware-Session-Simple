package Plack::Middleware::Session::Simple;

use 5.008005;
use strict;
use warnings;
use parent qw/Plack::Middleware/;
use Storable qw//;
use Digest::SHA1 ();
use Cookie::Baker;
use Plack::Util;
use Plack::Util::Accessor qw/
    cache
    keep_empty
    session_key
    path
    domain
    expires
    secure
    httponly
/;

our $VERSION = "0.01";

sub prepare_app {
    my $self = shift;

    $self->session_key('simple_session') unless $self->session_key;
    $self->path('/') unless defined $self->path;
    $self->keep_empty(1) unless defined $self->keep_empty;
}


sub call {
    my ($self,$env) = @_;

    my($id, $session) = $self->get_session($env);

    my $tied;
    if ($id && $session) {
        $tied = tie my %session, 
            'Plack::Middleware::Session::Simple::Session', %$session;
        $env->{'psgix.session'} = \%session;
        $env->{'psgix.session.options'} = {
            id => $id,
        };
    } else {
        $id = $self->generate_id($env);
        $tied = tie my %session, 
            'Plack::Middleware::Session::Simple::Session';
        $env->{'psgix.session'} = \%session;
        $env->{'psgix.session.options'} = {
            id => $id,
            new_session => 1,
        };
    }

    my $res = $self->app->($env);

    $self->response_cb(
        $res, sub {
            $self->finalize($env, $_[0], $tied)
        }
    );
}

sub get_session {
    my ($self, $env) = @_;
    my $id = crush_cookie($env->{HTTP_COOKIE} || '')->{$self->session_key};
    return unless defined $id;
    return unless $id =~ m!\A[0-9a-f]{37}!;

    my $session = $self->cache->get($id) or return;
    return ($id, $session);
}

sub generate_id {
    my ($self, $env) = @_;
    substr(Digest::SHA1::sha1_hex(rand() . $$ . {} . time),int(rand(4)),37);
}

sub finalize {
    my ($self, $env, $res, $session) = @_;
    my $options = $env->{'psgix.session.options'};
    my $new_session = delete $options->{new_session};

    my $need_store;
    if ( ($new_session && $self->keep_empty && ! $session->has_key )
             || $session->is_dirty
             || $options->{expire} || $options->{change_id}) {
        $need_store = 1;
    }
    $need_store = 0 if $options->{no_store};

    my $set_cookie;
    if ( ($new_session && $self->keep_empty && ! $session->has_key )
             || ($new_session && $session->is_dirty )
             || $options->{expire} || $options->{change_id}) {
        $set_cookie = 1;
    }

    if ( $need_store ) {
        if ($options->{expire}) {
            $self->cache->delete($options->{id});
        } elsif ($options->{change_id}) {
            $self->cache->delete($options->{id});
            $options->{id} = $self->generate_id($env);
            $self->cache->set($options->{id}, $session->untie);
        } else {
            $self->cache->set($options->{id}, $session->untie);
        }
    }

    if ( $set_cookie ) {
        if ($options->{expire}) {
            $self->_set_cookie($options->{id}, $res, %$options, expires => 'now'); 
        } else {
            $self->_set_cookie($options->{id}, $res, %$options); 
        }
    }
}

sub _set_cookie {
    my($self, $id, $res, %options) = @_;

    delete $options{id};

    $options{path}     = $self->path || '/' if !exists $options{path};
    $options{domain}   = $self->domain      if !exists $options{domain} && defined $self->domain;
    $options{secure}   = $self->secure      if !exists $options{secure} && defined $self->secure;
    $options{httponly} = $self->httponly    if !exists $options{httponly} && defined $self->httponly;

    if (!exists $options{expires} && defined $self->expires) {
        $options{expires} = $self->expires;
    }

    my $cookie = bake_cookie( 
        $self->session_key, {
            value => $id,
            %options,
        }
    );
    Plack::Util::header_push($res->[1], 'Set-Cookie', $cookie);
}

1;

package Plack::Middleware::Session::Simple::Session;

use strict;
use warnings;
use Tie::Hash;
use base qw/Tie::ExtraHash/;

sub TIEHASH {
    my $class = shift;
    bless [{@_},0], $class;
}

sub STORE {
    my $self = shift;
    $self->[1]++;
    $self->SUPER::STORE(@_);
}

sub DELETE {
    my $self = shift;
    $self->[1]++;
    $self->SUPER::DELETE(@_);
}

sub CLEAR {
    my $self = shift;
    $self->[1]++;
    $self->SUPER::CLEAR(@_);
}

sub is_dirty {
    $_[0]->[1];
}

sub untie : method  {
    return $_[0]->[0];
}

sub has_key {
    return scalar keys %{$_[0]->[0]};
} 

1;

__END__

=encoding utf-8

=head1 NAME

Plack::Middleware::Session::Simple - Make Session Simple

=head1 SYNOPSIS

    use Plack::Builder;
    use Cache::Memcached::Fast;

    my $app = sub {
        my $env = shift;
        my $counter = $env->{'psgix.session'}->{counter}++;
        [200,[], ["counter => $counter"]];
    };
    
    builder {
        enable 'Session::Simple',
            cache => Cache::Memcached::Fast->new({servers=>[..]}),
            session_key => 'myapp_session';
        $app
    };


=head1 DESCRIPTION

Plack::Middleware::Session::Simple is a yet another session management module.
This module supports psgix.session and psgi.session.options. And compatible with
Plack::Middleware::Session.
This middleware can reduce unnecessary accessing to cache Store and Set-Cookie header

=head1 LICENSE

Copyright (C) Masahiro Nagano.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Masahiro Nagano E<lt>kazeburo@gmail.comE<gt>

=cut

