# frozen_string_literal: true

require 'open3'
require 'tempfile'
require 'fileutils'

module Services
  module SendIt
    class DocumentationExplorer
      CACHE_DIR = File.expand_path('../../../data/sendit_docs_cache', __dir__)
      ENTRY_PATH = 'index.md'
      IMAGE_EXTENSIONS = %w[.png .jpg .jpeg].freeze
      INCLUDE_PATTERN = /\[include file="([^"]+)"\]/i.freeze
      LINK_PATTERN = /\[[^\]]+\]\(([^)]+)\)/.freeze
      MAX_FETCH_ATTEMPTS = 3
      RETRY_DELAY_SECONDS = 2

      def initialize(hub_client:, llm_client:, cache_dir: CACHE_DIR)
        @hub_client = hub_client
        @llm_client = llm_client
        @cache_dir = cache_dir
      end

      def call(entry_path: ENTRY_PATH)
        @documents = {}
        crawl(entry_path)
        @documents
      end

      private

      def crawl(path)
        normalized_path = normalize_path(path)
        return if normalized_path.empty?
        return if @documents.key?(normalized_path)

        if image_path?(normalized_path)
          @documents[normalized_path] = {
            path: normalized_path,
            type: 'image',
            content: extract_image_text(normalized_path)
          }
          return
        end

        content = fetch_document(normalized_path)
        @documents[normalized_path] = {
          path: normalized_path,
          type: 'text',
          content: content
        }

        linked_paths(content, current_path: normalized_path).each do |linked_path|
          crawl(linked_path)
        end
      end

      def linked_paths(content, current_path:)
        paths = content.scan(INCLUDE_PATTERN).flatten
        paths.concat(content.scan(LINK_PATTERN).flatten)

        paths.filter_map do |path|
          resolve_path(current_path, path)
        end.uniq
      end

      def resolve_path(current_path, path)
        value = path.to_s.strip
        return nil if value.empty?
        return nil if value.start_with?('#')

        if value.start_with?('http://', 'https://')
          docs_prefix = @hub_client.spk_document_url('')
          return nil unless value.start_with?(docs_prefix)

          value = value.delete_prefix(docs_prefix)
        end

        base_dir = File.dirname(current_path)
        normalized = File.expand_path(value, "/#{base_dir}")
        normalize_path(normalized)
      end

      def normalize_path(path)
        path.to_s.sub(%r{\A/+}, '')
      end

      def image_path?(path)
        IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
      end

      def extract_image_text(path)
        image_url = @hub_client.spk_document_url(path)
        @llm_client.extract_text_from_image(image_url: image_url)
      rescue StandardError => e
        warn "Image extraction via LLM failed for #{path}: #{e.message}. Falling back to local OCR."
        extract_image_text_locally(path)
      end

      def extract_image_text_locally(path)
        Tempfile.create([File.basename(path, '.*'), File.extname(path)]) do |file|
          file.binmode
          file.write(fetch_document(path))
          file.flush

          stdout, stderr, status = Open3.capture3('/usr/bin/swift', '-', stdin_data: swift_ocr_script(file.path))
          text = stdout.to_s.strip
          return text if status.success? && !text.empty?

          raise ArgumentError, "Local OCR failed for #{path}: #{stderr}"
        end
      end

      def swift_ocr_script(image_path)
        <<~SWIFT
          import Foundation
          import Vision
          import AppKit

          let imageURL = URL(fileURLWithPath: #{image_path.dump})
          guard let image = NSImage(contentsOf: imageURL) else {
              fputs("Could not load image\\n", stderr)
              exit(1)
          }

          var rect = CGRect(origin: .zero, size: image.size)
          guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
              fputs("Could not extract CGImage\\n", stderr)
              exit(1)
          }

          let request = VNRecognizeTextRequest()
          request.recognitionLevel = .accurate
          request.usesLanguageCorrection = false

          let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

          do {
              try handler.perform([request])
              let observations = request.results ?? []
              for observation in observations {
                  if let candidate = observation.topCandidates(1).first {
                      print(candidate.string)
                  }
              }
          } catch {
              fputs("OCR failed: \(error)\\n", stderr)
              exit(1)
          }
        SWIFT
      end

      def fetch_document(path)
        content = fetch_remote_document(path)
        write_cache(path, content)
        content
      rescue StandardError => e
        cached = read_cache(path)
        return cached if cached

        raise e
      end

      def fetch_remote_document(path)
        attempts = 0

        begin
          attempts += 1
          @hub_client.fetch_spk_document(path: path)
        rescue StandardError => e
          raise e if attempts >= MAX_FETCH_ATTEMPTS

          warn "Retrying SPK document fetch for #{path} after error: #{e.message}"
          sleep(RETRY_DELAY_SECONDS)
          retry
        end
      end

      def write_cache(path, content)
        cache_path = cache_path_for(path)
        FileUtils.mkdir_p(File.dirname(cache_path))
        File.binwrite(cache_path, content)
      end

      def read_cache(path)
        cache_path = cache_path_for(path)
        return nil unless File.exist?(cache_path)

        File.binread(cache_path)
      end

      def cache_path_for(path)
        File.join(@cache_dir, path)
      end
    end
  end
end
