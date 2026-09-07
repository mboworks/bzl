Some rules for the code layout and its development.

* Everything is under the Apache 2.0 license, see [LICENSE](LICENSE).
* All sources must be unix-text files: https://en.wikipedia.org/wiki/Text_file
  * Lines end in {LF}.
  * The files are either empty or end in {LF}.
* All code must be formatted using the relevant formatters, as enforced by pre-commit.
  * This provides consistent formatting.
  * The choices are meant to enable fast structural reading by humans.
  * It cares less about writing because there is auto formatting and code is
    read much more often than written.
  * Auto formatting also prevents pointless discussions like where '*' goes.
  * The guide mostly follows Google style: https://google.github.io/styleguide/
* All exported library code is in the directory 'bzl'.
* All public / exported code must:
  * be tested,
  * have documentation.
* API changes that are not backwards compatible should not occur in minor version changes.
* Undocumented and private/internal APIs may be changed in any way at any time.
