# ICK

Isomorphismes' C Kompiler.

ICK is the general/C compiler line. IRK is the separate R experiment.

The first shared component is a small meaning model for turning words in a
binding name into proposed compiler claims. For example, `image` or a close
word such as `picture` can propose the semantic kind `Image`. A target compiler
must then check that claim with actual type evidence; vector similarity is not
the check.

The model is deliberately the same pinned artifact used by IRK so that a word
does not change meaning merely because the output language changed.

```sh
sh model/fetch.sh
```

The working R prototype lives at https://github.com/isomorphisms/irk.

