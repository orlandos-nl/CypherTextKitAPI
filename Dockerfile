FROM swift:5.6-focal as builder
WORKDIR /root
ARG environment=development
COPY . .
RUN swift build -c release
RUN export executable=swift build -c release --show-bin-path
RUN echo $executable

FROM swift:slim
WORKDIR /app
COPY --from=builder /app .
RUN swift build -c release --show-bin-path
EXPOSE 8080
CMD [".build/release/${executable}", "serve", "--env", $environment, "0.0.0.0", "--port", "8080"]
