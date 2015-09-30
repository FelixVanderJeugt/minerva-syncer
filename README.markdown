
Minerva Syncer
==============

This is a bash script which utilizes curl to sync a local folder with
the documents on [Minerva](http://minerva.ugent.be). It should
automatically download new files, ask to update changed files, ...
(general syncing stuff)

Anyone who finds bugs and stuff, please tell me about them. Do not
fear testing, I've written no computer/Minerva breaking code.

Notes
-----

The script stores its config file in `$XDG_CONFIG_HOME/minerva-syncer`.
On the first run, you'll be able to choose some settings. For now,
changing these settings is done manually by editing the `config` file.

