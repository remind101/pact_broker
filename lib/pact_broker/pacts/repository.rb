require 'digest/sha1'
require 'sequel'
require 'ostruct'
require 'pact_broker/logging'
require 'pact_broker/pacts/pact_publication'
require 'pact_broker/pacts/all_pact_publications'
require 'pact_broker/pacts/all_pacts'
require 'pact_broker/pacts/latest_pacts'
require 'pact_broker/pacts/latest_tagged_pacts'
require 'pact/shared/json_differ'
require 'pact_broker/domain'

module PactBroker
  module Pacts
    class Repository

      include PactBroker::Logging

      def create params
        PactPublication.new(
          consumer_version_id: params[:version_id],
          provider_id: params[:provider_id],
          pact_version: find_or_create_pact_version(params.fetch(:consumer_id), params.fetch(:provider_id), params[:json_content]),
        ).save.to_domain
      end

      def update id, params
        existing_model = PactPublication.find(id: id)
        pact_version = find_or_create_pact_version(existing_model.consumer_version.pacticipant_id, existing_model.provider_id, params[:json_content])
        if existing_model.pact_version_id != pact_version.id
          PactPublication.new(
            consumer_version_id: existing_model.consumer_version_id,
            provider_id: existing_model.provider_id,
            revision_number: (existing_model.revision_number + 1),
            pact_version: pact_version,
          ).save.to_domain
        else
          existing_model.to_domain
        end
      end

      def delete params
        id = AllPactPublications
          .consumer(params.consumer_name)
          .provider(params.provider_name)
          .consumer_version_number(params.consumer_version_number)
          .select(:id)
        PactPublication.where(id: id).delete
      end

      def find_all_pact_versions_between consumer_name, options
        AllPacts
          .eager(:tags)
          .consumer(consumer_name)
          .provider(options.fetch(:and))
          .reverse_order(:consumer_version_order)
          .collect(&:to_domain)
      end

      def find_latest_pact_versions_for_provider provider_name, tag = nil
        if tag
          LatestTaggedPacts.provider(provider_name).where(tag_name: tag).collect(&:to_domain)
        else
          LatestPacts.provider(provider_name).collect(&:to_domain)
        end
      end

      def find_by_version_and_provider version_id, provider_id
        AllPacts
          .eager(:tags)
          .where(consumer_version_id: version_id, provider_id: provider_id)
          .limit(1).collect(&:to_domain_with_content)[0]
      end

      def find_latest_pacts
        LatestPacts.collect(&:to_domain_without_tags)
      end

      def find_latest_pact(consumer_name, provider_name, tag = nil)
        query = AllPacts
          .consumer(consumer_name)
          .provider(provider_name)
        query = query.tag(tag) unless tag.nil?
        query.latest.all.collect(&:to_domain_with_content)[0]
      end

      def find_pact consumer_name, consumer_version, provider_name, revision_number = nil
        query = revision_number ? AllPactPublications.revision_number(revision_number) : AllPacts
        query
          .eager(:tags)
          .consumer(consumer_name)
          .provider(provider_name)
          .consumer_version_number(consumer_version)
          .limit(1).collect(&:to_domain_with_content)[0]
      end

      def find_previous_pact pact
        AllPacts
          .eager(:tags)
          .consumer(pact.consumer.name)
          .provider(pact.provider.name)
          .consumer_version_order_before(pact.consumer_version.order)
          .latest.collect(&:to_domain_with_content)[0]
      end

      def find_next_pact pact
        AllPacts
          .eager(:tags)
          .consumer(pact.consumer.name)
          .provider(pact.provider.name)
          .consumer_version_order_after(pact.consumer_version.order)
          .earliest.collect(&:to_domain_with_content)[0]
      end

      def find_previous_distinct_pact pact
        previous, current = nil, pact
        loop do
          previous = find_previous_distinct_pact_by_sha current
          return previous if previous.nil? || different?(current, previous)
          current = previous
        end
      end

      private

      def find_previous_distinct_pact_by_sha pact
        current_pact_content_sha =
          AllPacts.select(:pact_version_sha)
          .consumer(pact.consumer.name)
          .provider(pact.provider.name)
          .consumer_version_number(pact.consumer_version_number)
          .limit(1)

        AllPacts
          .eager(:tags)
          .consumer(pact.consumer.name)
          .provider(pact.provider.name)
          .consumer_version_order_before(pact.consumer_version.order)
          .where('pact_version_sha != ?', current_pact_content_sha)
          .latest
          .collect(&:to_domain_with_content)[0]
      end

      def different? pact, other_pact
        Pact::JsonDiffer.(pact.content_hash, other_pact.content_hash, allow_unexpected_keys: false).any?
      end

      def find_or_create_pact_version consumer_id, provider_id, json_content
        sha = Digest::SHA1.hexdigest(json_content)
        PactVersion.find(sha: sha, consumer_id: consumer_id, provider_id: provider_id) || create_pact_version(consumer_id, provider_id, sha, json_content)
      end

      def create_pact_version consumer_id, provider_id, sha, json_content
        PactBroker.logger.debug("Creating new PactVersion for sha #{sha}")
        pact_version = PactVersion.new(consumer_id: consumer_id, provider_id: provider_id, sha: sha, content: json_content)
        pact_version.save
      end

    end
  end
end
