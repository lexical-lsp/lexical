# Used to build a clean container for testing the Lexical boot sequence.
#
# Build: docker build -t lx -f integration/Dockerfile .
# Run:   docker run -it lx

ARG ELIXIR_VERSION=1.15.6
ARG ERLANG_VERSION=26.1.1

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-ubuntu-jammy-20230126

RUN apt-get update
RUN apt-get install -y \
  git \
  curl \
  unzip \
  # used to compile erlang
  build-essential \
  autoconf \
  openssl \
  libssl-dev

WORKDIR /lexical

COPY integration/boot/set_up_rtx.sh integration/boot/set_up_rtx.sh
RUN integration/boot/set_up_rtx.sh

COPY integration/boot/set_up_asdf.sh integration/boot/set_up_asdf.sh
RUN integration/boot/set_up_asdf.sh

COPY apps apps
COPY bin bin
COPY config config
COPY priv priv
COPY projects projects
COPY mix* .

COPY integration/boot/set_up_lexical.sh integration/boot/set_up_lexical.sh
RUN integration/boot/set_up_lexical.sh

CMD bash
