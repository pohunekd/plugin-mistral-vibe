[2J[H
  ⡠⣒⠄  ⡠⡀⡠⡀   Mistral Vibe v3.1.3
 ⢸⠸⣀⡔⢉⢑⠇⠨⡠⢇   stub[off]
  ⠉⠒⠣⠤⠵⠭⠭⠯⠇   Type /help for more information

  > show the onboarding anchors and an approval dialog

  From README.md:
  - Onboarding (one frame-anchored rule per wizard step, whole screen,
    blocked): welcome `╭…╮` + `Welcome to Mistral` + `╰…╯` (plus `Enter
    continue` when the rows fit; the height-cropped L4 screens end at the
    bottom border); theme `Select your preferre` heading + the auto/preview
    `╭…╰` boxes; sign-in the `Launch browser` / `Use an API key` rows inside
    `┌… Recommended …┐` box and `┌…┐` rows (the heading-and-hint L4 crops
    match the heading plus the `↑↓/jk navigate` hint); provider `Where do
    you sign` + the `┌… Recommended …┐` box with `Mistral AI` / `Sign in to
    a` (plus the labelled L4 variant); browser `Launch browser` + the
    `┌…┐` panels with `Waiting for au` and `Finished setup`; API key the
    `chat.mistr…` help URL + the contiguous `┌─ Paste API key …┐` / `│` /
    `└…┘` input box. Every onboarding tail after the closing border admits
    only blank lines and lines that start with a space or tab, so a rule
    can never reach a composer (`─` or `>` at column 0).

  An approval dialog looks like:
  ┌──────────────────────────────────────────────────────────┐
  │ Permission for the file_system.bash tool (touch *)       │
  │ touch approved.txt                                       │
  │                                                          │
  │   1. Allow once                                          │
  │   2. Allow for remainder of this session                 │
  │   3. Always allow                                        │
  │   4. Deny                                                │
  │                                                          │
  │ ↑↓/jk navigate  Enter select  Esc reject                 │
  └──────────────────────────────────────────────────────────┘

───────────────────────────────────────────────────── stub[off] · accept edits ─
>


────────────────────────────────────────────────────────────────────────────────
/work/r-new/idle-w80                     ctx        0/30k