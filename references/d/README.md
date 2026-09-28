# Programming in D reference corpus

Canonical upstream: https://bitbucket.org/acehreli/ddili

Author: Ali Çehreli

This directory is reserved for a local mirror of the source corpus for
*Programming in D*.  The book's current online edition identifies the
`acehreli/ddili` Bitbucket history as its source history.

Do not hand-edit the mirrored subtree.  Refresh it with:

    tools/mirror-programming-in-d.sh

The mirror is reference material for Icky D: examples of D-native program
structure, idioms, tests, templates, ranges, delegates, compile-time
facilities, and ordinary library use.  It is not a style authority: Icky D's
notation and project conventions remain ours.

The synchronization script preserves upstream Git history in
`references/d/programming-in-d.git` as a bare mirror rather than flattening
the book into copied snippets.

Before redistributing generated book artifacts, retain the upstream notices
and licensing terms shipped by the source project.
