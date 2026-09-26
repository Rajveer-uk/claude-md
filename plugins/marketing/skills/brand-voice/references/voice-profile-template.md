# Voice profile — how to build `brand/voice.md`

Load this file only when a project has no voice profile yet, or the owner asks to rebuild one. The skeleton below matches `templates/brand-voice.md` in the claude-md repo; keep the two in step.

## Build it from evidence, not adjectives

1. **Collect 3–5 pieces the owner approved** — shipped pages, sent emails, posts they liked. Their approval is the evidence. No samples → ask for them. Don't draft a profile from a description like "friendly but professional"; that fits every brand.
2. **Extract what a writer can copy:** sentence length, contractions, how fast the point arrives, what the product is called, words that never appear in any sample.
3. **Turn traits into pairs.** Each "We are" gets a "We are not" that names the likely over-correction (direct → not curt; warm → not gushing).
4. **Fill the channel table** only for channels the brand actually uses.
5. **Claims section:** ask the owner which words need conditions, which disclaimers are mandatory, and who signs off. Leave "none" rather than guessing.
6. **Show the owner the draft profile** and save it as `brand/voice.md` only after they approve it; log `Updated: <date> — initial profile — <sources>`.

Keep the file under ~120 lines; it's read on every draft. Wording bans belong in `brand/banned-phrases.txt`, where the guards `content-lint` step enforces them.

## Skeleton

```markdown
# Brand voice — <APP_NAME>

**Personality:** if <APP_NAME> were a person, they would be <one line>.
**Readers:** <primary reader — role, expertise, what they care about>. Secondary: <...>.
**Built:** YYYY-MM-DD from <n> approved pieces (<which>).

## Voice — constant on every channel

| We are | We are not |
|---|---|
| **<Attribute>** — <what it looks like on the page> | **<Boundary>** — <the misreading to avoid> |
| **<Attribute>** — <...> | **<Boundary>** — <...> |
| **<Attribute>** — <...> | **<Boundary>** — <...> |

- **Sounds like:** "<one sentence in our voice>"
- **Doesn't sound like:** "<one sentence that breaks it>"

## Tone — flexes by channel

| Channel | Formality | Energy | Technical depth | Notes |
|---|---|---|---|---|
| Blog / guide | <low / medium / high> | <...> | <...> | <e.g. lead with the example> |
| Landing page / ad | <...> | <...> | <...> | one primary CTA |
| Email | <...> | <...> | <...> | subject line matches the body |
| Social | <...> | <...> | <...> | <...> |
| Support / help | <...> | <...> | <...> | <...> |

## Terminology and house style

| Use | Not | Why |
|---|---|---|
| <product name exactly as written> | <wrong forms> | <...> |
| <preferred term> | <avoided term> | <...> |

House style: <spelling UK/US> · <Oxford comma yes/no> · <sentence-case or title-case headings> · <numbers: words to nine, then digits> · <date format>.

## Claims and compliance

- Every figure, rate, fee, price, discount, percentage, return, guarantee, comparison, quote or testimonial comes from supplied source material. Missing → write `[VERIFY: <what is needed>]`; never a guessed value.
- Words that must carry their qualifying conditions in the same sentence: <e.g. "free", "guaranteed", "secure", "protected">.
- Required disclaimers: <channel → exact wording>, or "none".
- Rules that apply: <e.g. financial-promotion rules, advertising code, none>.
- Sign-off before publishing: <role> for <content types>.

## Severity (for reviews)

| Severity | Means | Example from our own work |
|---|---|---|
| High | Crosses a "We are not", makes an unsupported or non-compliant claim, or breaks a `mkt/` ledger row or banned phrase | <...> |
| Medium | Right voice, wrong tone for the channel; wrong terminology | <...> |
| Low | Style preference or polish | <...> |

## Reference sample

<One short approved piece, verbatim. Every draft is held to this bar.>

## Updated log (append only)

Updated: YYYY-MM-DD — initial profile — built from <n> approved pieces
```
