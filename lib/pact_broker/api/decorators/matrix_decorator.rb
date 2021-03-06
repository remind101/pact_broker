require 'ostruct'
require 'pact_broker/api/pact_broker_urls'

module PactBroker
  module Api
    module Decorators
      class MatrixDecorator
        include PactBroker::Api::PactBrokerUrls

        def initialize(lines)
          @lines = lines
        end

        def to_json(options)
          to_hash(options).to_json
        end

        def to_hash(options)
          {
            summary: {
              deployable: deployable,
              reason: reason
            },
            matrix: matrix(lines, options[:user_options][:base_url])
          }
        end

        def deployable
          return nil if lines.empty?
          return nil if lines.any?{ |line| line[:success].nil? }
          lines.any? && lines.all?{ |line| line[:success] }
        end

        def reason
          return "No results matched the given query" if lines.empty?
          case deployable
          when true then "All verification results are published and successful"
          when false then "One or more verifications have failed"
          else
            "Missing one or more verification results"
          end
        end

        private

        attr_reader :lines

        def matrix(lines, base_url)
          provider = nil
          consumer = nil
          lines.collect do | line |
            provider ||= OpenStruct.new(name: line[:provider_name])
            consumer ||= OpenStruct.new(name: line[:consumer_name])
            consumer_version = OpenStruct.new(number: line[:consumer_version_number], pacticipant: consumer)
            line_hash(consumer, provider, consumer_version, line, base_url)
          end
        end

        def line_hash(consumer, provider, consumer_version, line, base_url)
          {
            consumer: consumer_hash(line, consumer, consumer_version, base_url),
            provider: provider_hash(line, provider, base_url),
            pact: pact_hash(line, base_url),
            verificationResult: verification_hash(line, base_url)
          }
        end

        def consumer_hash(line, consumer, consumer_version, base_url)
          {
            name: line[:consumer_name],
            version: {
              number: line[:consumer_version_number],
              _links: {
                self: {
                  href: version_url(base_url, consumer_version)
                }
              }
            },
            _links: {
              self: {
                href: pacticipant_url(base_url, consumer)
              }
            }
          }
        end

        def provider_hash(line, provider, base_url)
          hash = {
            name: line[:provider_name],
            version: nil,
            _links: {
              self: {
                href: pacticipant_url(base_url, provider)
              }
            }
          }

          if !line[:provider_version_number].nil?
            hash[:version] = { number: line[:provider_version_number] }
          end

          hash
        end

        def pact_hash(line, base_url)
          {
            createdAt: line[:pact_created_at].to_datetime.xmlschema,
            _links: {
              self: {
                href: pact_url_from_params(base_url, line)
              }
            }
          }
        end

        def verification_hash(line, base_url)
          if !line[:success].nil?
            {
              success: line[:success],
              verifiedAt: line[:verification_executed_at].to_datetime.xmlschema,
              _links: {
                self: {
                  href: verification_url(OpenStruct.new(line.merge(number: line[:verification_number])), base_url)
                }
              }
            }
          else
            nil
          end
        end
      end
    end
  end
end
