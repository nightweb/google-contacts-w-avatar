Warning
===
This is still a work in progress. The API for modifying elements will be cleaned up to remove the need for hackish data management for updating elements, everything else should be final.

Overview
===
Reduces the complexity for dealing with importing and exporting using the [Google Contacts v3](https://developers.google.com/google-apps/contacts/v3/) && [Google Contacts v2](https://developers.google.com/google-apps/contacts/v2/) API. Handles preserving the existing data and modifying any new data added without having to deal with it yourself. Supports with photo (avatar) management.
Based on original gem google-contacts. See https://github.com/Placester/google-contacts

Example usage
===
Rails 3 and Rails 4
-
add to Gemfile:
gem 'google-contacts-w-avatar', git: 'https://github.com/nightweb/google-contacts-w-avatar.git'

authorize:
gc = GoogleContacts::Auth::UserLogin.new(google_email,some_password).google_contacts

fetch all elements:
el = gc.all

Warnining! By default not load contact photo. your must get element by id or use gc.get_photo(el) for upload image

fetch element by id:

el = gc.get(id)

update photo:

el = gc.update_photo!(el, path_to_your_photo)



Compability
-
Tested against Ruby 2.0.0.

Documentation
-
See http://rubydoc.info/github/nightweb/google-contacts-w-avatar/master/frames for full documentation.

License
-
Dual licensed under MIT and GPL.
=======
google-contacts-w-avatar
========================

Helps manage both the importing and exporting of Google Contacts (v2 &amp;&amp; v3) data (include manage avatars)
