# NAME

Plack::Middleware::Session::Simple - Make Session Simple

# SYNOPSIS

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



# DESCRIPTION

Plack::Middleware::Session::Simple is a yet another session management module.
This module supports psgix.session and psgi.session.options. And compatible with
Plack::Middleware::Session.
This middleware can reduce unnecessary accessing to cache Store and Set-Cookie header

# LICENSE

Copyright (C) Masahiro Nagano.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Masahiro Nagano <kazeburo@gmail.com>
