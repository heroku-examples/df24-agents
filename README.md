# Dreamforce 2024 Building Agentic AI Applications with Heroku

This is the workshop code for the Dreamforce 2024 session "Building Agentic AI Applications with Heroku".

## Running the Workshop

Each "step" is self-contained. Before you can run the steps, you will need Ruby `3.3.4` installed on your machine.

1. Install dependencies:

```bash
bundle install
```

2. Copy `.env.example` to `.env` and fill in the necessary values.
   a. The `DYNO_INTEROP_TOKEN` is the token for the Dyno Interop service.
   b. The `DYNO_INTEROP_BASE_URL` is the URL of the Dyno Interop service.

3. Run each step with `./step1` or `./step2` etc.
