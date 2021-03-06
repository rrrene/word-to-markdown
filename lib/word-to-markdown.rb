require 'reverse_markdown'
require 'descriptive_statistics'
require 'premailer'

class WordToMarkdown

  HEADING_DEPTH = 6 # Number of headings to guess, e.g., h6
  HEADING_STEP = 100/HEADING_DEPTH
  MIN_HEADING_SIZE = 20

  LI_SELECTORS = %w[
    MsoListParagraphCxSpFirst
    MsoListParagraphCxSpMiddle
    MsoListParagraphCxSpLast
  ]

  attr_reader :path, :doc

  # Create a new WordToMarkdown object
  #
  # input - a HTML string or path to an HTML file
  #
  # Returns the WordToMarkdown object
  def initialize(input)
    path = File.expand_path input, Dir.pwd
    if File.exist?(path)
      html = File.open(path).read
      @path = path
    else
      @path = String
      html = input.to_s
    end
    @doc = Nokogiri::HTML normalize(html)
    semanticize!
  end

  # Perform pre-processing normalization
  def normalize(html)
    encoding = encoding(html)
    html = html.force_encoding(encoding).encode("UTF-8", :invalid => :replace, :replace => "")
    html = Premailer.new(html, :with_html_string => true, :input_encoding => "UTF-8").to_inline_css
    html.gsub! /\<\/?o:[^>]+>/, "" # Strip everything in the office namespace
    html.gsub! /\n|\r/," "         # Remove linebreaks
    html.gsub! /“|”/, '"'          # Straighten curly double quotes
    html.gsub! /‘|’/, "'"          # Straighten curly single quotes
    html
  end

  def inspect
    "<WordToMarkdown path=\"#{@path}\">"
  end

  def to_s
    @markdown ||= scrub_whitespace(ReverseMarkdown.parse(html))
  end

  def html
    doc.to_html
  end

  def encoding(html)
    match = html.encode("UTF-8", :invalid => :replace, :replace => "").match(/charset=([^\"]+)/)
    if match
      match[1].sub("macintosh", "MacRoman")
    else
      "UTF-8"
    end
  end

  def scrub_whitespace(string)
    string.sub!(/\A[[:space:]]+/,'')                # leading whitespace
    string.sub!(/[[:space:]]+\z/,'')                # trailing whitespace
    string.gsub!(/\n\n \n\n/,"\n\n")                # Quadruple line breaks
    string.gsub!(/^([0-9]+)\.[[:space:]]*/,"\\1. ") # Numbered lists
    string.gsub!(/^-[[:space:]·]*/,"- ")            # Unnumbered lists
    string.gsub!(/\u00A0/, "")                      # Unicode non-breaking spaces, injected as tabs
    string.gsub!(/^ /, "")                          # Leading spaces
    string.gsub!(/^- (\d+)\./, "\\1.")              # OL's wrapped in UL's see http://bit.ly/1ivqxy8
    string
  end

  # Returns an array of Nokogiri nodes that are implicit headings
  def implicit_headings
    @implicit_headings ||= begin
      headings = []
      doc.css("[style]").each do |element|
        headings.push element unless element.font_size.nil? || element.font_size < MIN_HEADING_SIZE
      end
      headings
    end
  end

  # Returns an array of font-sizes for implicit headings in the document
  def font_sizes
    @font_sizes ||= begin
      sizes = []
      doc.css("[style]").each do |element|
        sizes.push element.font_size.round(-1) unless element.font_size.nil?
      end
      sizes.uniq.sort
    end
  end

  # Given a Nokogiri node, guess what heading it represents, if any
  def guess_heading(node)
    return nil if node.font_size == nil
    [*1...HEADING_DEPTH].each do |heading|
      return "h#{heading}" if node.font_size >= h(heading)
    end
    nil
  end

  # Minimum font size required for a given heading
  # e.g., H(2) would represent the minimum font size of an implicit h2
  def h(n)
    font_sizes.percentile ((HEADING_DEPTH-1)-n) * HEADING_STEP
  end

  # Try to make semantic markup explicit where implied by the export
  def semanticize!
    # Convert unnumbered list paragraphs to actual unnumbered lists
    doc.css(".#{LI_SELECTORS.join(",.")}").each { |node| node.node_name = "li" }

    # Try to guess heading where implicit bassed on font size
    implicit_headings.each do |element|
      heading = guess_heading element
      element.node_name = heading unless heading.nil?
    end

    # Removes paragraphs from tables
    doc.search("td p").each { |node| node.node_name = "span" }
  end
end

module Nokogiri
  module XML
    class Element

      FONT_SIZE_REGEX = /\bfont-size:\s?([0-9\.]+)pt;?\b/

      def font_size
        @font_size ||= begin
          match = FONT_SIZE_REGEX.match attr("style")
          match[1].to_i unless match.nil?
        end
      end
    end
  end
end
