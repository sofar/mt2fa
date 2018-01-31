
## mt2fa - authenticate using your email

Enables server to allow users to add an extra layer of security and verify
their identity using their email address.

## License

 (C) 2018 Auke Kok <sofar@foo-projects.org>

 Permission to use, copy, modify, and/or distribute this software
 for any purpose with or without fee is hereby granted, provided
 that the above copyright notice and this permission notice appear
 in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR
BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS
SOFTWARE.

## chatcommands

These commands require the `server` privilege.

  `/mt2fa register <email>`

  Required. Until registration is complete, only players with the `server`
  priv will be able to log in. This command will perform a `server`
  registration that will need confirmation.

  `/mt2fa ipchange <email>`

  If the server changes IP address, this will need confirmation. The email
  must be the same as the original registration address. This action will
  need confirmation. Until the ipchange is confirmed, no other actions will
  be allowed by the mt2fa server.

## settings

  `mt2fa.require_registration bool false`

  All player must register if set to `true`

  `mt2fa.require_authentication bool false`

  All players must authenticate if set to `true`

  `mt2fa.api_server string https://mt2fa.foo-projects.org/mt2fa`

  Adress to the mt2fa API server.

  `mt2fa.grace int 300`

  How long (seconds) a player can take to perform required authentication
  and/or registration.

  `mt2fa.registration_grants` string nil

  Privileges that are granted to players that have successfully registered.
  Should be a string value separated by commas, without spaces.

## player attributes

  `mt2fa.registered int nil`

  This player has previously registered.

  `mt2fa.auth_required int nil`

  This player must authenticate.

