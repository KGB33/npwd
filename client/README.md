# New Page Who Dis -- Client

Run:

```sh
gleam run -m lustre/dev build --outdir=../server/priv/static # Build 
cd ../server/ && gleam run
```

Test:

```
gleam test 
```

# Folder Structure

```
src
├── compontents
│   └── character
│       ├── character.gleam  # Boilerplate/compont registration
│       ├── model.gleam
│       ├── update.gleam
│       └── view.gleam
├── services                 # API calls
│   └── character.gleam
└── client.gleam             # Main file
```
