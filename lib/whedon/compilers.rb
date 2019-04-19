# This module has methods to compile PDFs and Crossref XML depending upon
# the content type of the paper (Markdown or LaTeX)
module Compilers
  # Generate the paper PDF
  # Optionally pass in a custom branch name as first param
  def generate_pdf(custom_branch=nil,paper_issue=nil, paper_volume=nil, paper_year=nil)
    if paper.latex_source?
      pdf_from_latex(custom_branch, paper_issue, paper_volume, paper_year)
    elsif paper.markdown_source?
      pdf_from_markdown(custom_branch, paper_issue, paper_volume, paper_year)
    end
  end

  def generate_crossref(paper_issue=nil, paper_volume=nil, paper_year=nil, paper_month=nil, paper_day=nil)
    if paper.latex_source?
      crossref_from_latex(paper_issue=nil, paper_volume=nil, paper_year=nil, paper_month=nil, paper_day=nil)
    elsif paper.markdown_source?
      crossref_from_markdown(paper_issue=nil, paper_volume=nil, paper_year=nil, paper_month=nil, paper_day=nil)
    end
  end

  def pdf_from_latex(custom_branch=nil,paper_issue=nil, paper_volume=nil, paper_year=nil)
    puts "Compiling from LaTeX source"

    # Optionally pass a custom branch name
    `cd #{paper.directory} && git checkout #{custom_branch} --quiet` if custom_branch

    metadata = YAML.load_file("#{paper.directory}/paper.yml")

    for k in ["title", "authors", "affiliations", "keywords", "bibliography"]
    	raise "Key #{k} not present in metadata" unless metadata.keys().include?(k)
    end

    # ENV variables or default for issue/volume/year
    issue = ENV["JLCON_ISSUE"] === nil ? 1 : ENV["JLCON_ISSUE"]
    volume = ENV["JLCON_VOLUME"] === nil ? 1 : ENV["JLCON_VOLUME"]
    year = ENV["JLCON_YEAR"] === nil ? 2019 : ENV["JLCON_YEAR"]
    journal_name = ENV["JOURNAL_NAME"]

    `cd #{paper.directory} && rm *.aux \
    && rm *.blg && rm *.fls && rm *.log\
    && rm *.fdb_latexmk`

    open("#{paper.directory}/header.tex", 'w') do |f|
      f << "% **************GENERATED FILE, DO NOT EDIT**************\n\n"
      f << "\\title{#{metadata["title"]}}\n\n"
      for auth in metadata["authors"]
        f << "\\author[#{auth["affiliation"]}]{#{auth["name"]}}\n"
      end
      for aff in metadata["affiliations"]
        f << "\\affil[#{aff["index"]}]{#{aff["name"]}}\n"
      end
      f << "\n\\keywords{"
      for i in 0...metadata["keywords"].length-1
        f << "#{metadata["keywords"][i]}, "
      end
      f << metadata["keywords"].last
      f << "}\n\n"
    end

    open("#{paper.directory}/journal_dat.tex", 'w') do |f|
      f << "% **************GENERATED FILE, DO NOT EDIT**************\n\n"
      f << "\\def\\@journalName{#{journal_name}}\n"
      f << "\\def\\@volume{#{volume}}\n"
      f << "\\def\\@issue{#{issue}}\n"
      f << "\\def\\@year{#{year}}\n"
    end

    open("#{paper.directory}/bib.tex", 'w') do |f|
      f << "% **************GENERATED FILE, DO NOT EDIT**************\n\n"
      f << "\\bibliographystyle{juliacon}\n"
      f << "\\bibliography{#{metadata["bibliography"]}}\n"
    end

    `cd #{paper.directory} && latexmk -f -bibtex -pdf paper.tex`

    if File.exists?("#{paper.directory}/paper.pdf")
      `mv #{paper.directory}/paper.pdf #{paper.directory}/#{paper.filename_doi}.pdf`
      puts "#{paper.directory}/#{paper.filename_doi}.pdf"
    else
      abort("Looks like we failed to compile the PDF")
    end
  end

  def pdf_from_markdown(custom_branch=nil,paper_issue=nil, paper_volume=nil, paper_year=nil)
    puts "Compiling from Markdown"
    latex_template_path = "#{Whedon.resources}/#{ENV['JOURNAL_ALIAS']}/latex.template"
    csl_file = "#{Whedon.resources}/#{ENV['JOURNAL_ALIAS']}/apa.csl"

    # TODO: Sanitize all the things!
    paper_title = paper.title.gsub!('_', '\_')
    plain_title = paper.plain_title.gsub('_', '\_').gsub('#', '\#')
    paper_year ||= Time.now.strftime('%Y')
    paper_issue ||= @current_issue
    paper_volume ||= @current_volume
    # FIX ME - when the JOSS application has an actual API this could/should
    # be cleaned up
    # submitted = `curl #{ENV['JOURNAL_URL']}/papers/lookup/#{@review_issue_id}`
    submitted = Time.now.strftime('%d %B %Y')
    published = Time.now.strftime('%d %B %Y')

    # Optionally pass a custom branch name
    `cd #{paper.directory} && git checkout #{custom_branch} --quiet` if custom_branch

    # TODO: may eventually want to swap out the latex template
    `cd #{paper.directory} && pandoc \
    -V repository="#{repository_address}" \
    -V archive_doi="#{archive_doi}" \
    -V paper_url="#{paper.pdf_url}" \
    -V journal_name='#{ENV['JOURNAL_NAME']}' \
    -V formatted_doi="#{paper.formatted_doi}" \
    -V review_issue_url="#{paper.review_issue_url}" \
    -V graphics="true" \
    -V issue="#{paper_issue}" \
    -V volume="#{paper_volume}" \
    -V page="#{paper.review_issue_id}" \
    -V logo_path="#{Whedon.resources}/#{ENV['JOURNAL_ALIAS']}/logo.png" \
    -V year="#{paper_year}" \
    -V submitted="#{submitted}" \
    -V published="#{published}" \
    -V formatted_doi="#{paper.formatted_doi}" \
    -V citation_author="#{paper.citation_author}" \
    -V paper_title='#{paper.title}' \
    -V footnote_paper_title='#{plain_title}' \
    -o #{paper.filename_doi}.pdf -V geometry:margin=1in \
    --pdf-engine=xelatex \
    --filter pandoc-citeproc #{File.basename(paper.paper_path)} \
    --from markdown+autolink_bare_uris \
    --csl=#{csl_file} \
    --template #{latex_template_path}`

    if File.exists?("#{paper.directory}/#{paper.filename_doi}.pdf")
      puts "#{paper.directory}/#{paper.filename_doi}.pdf"
    else
      abort("Looks like we failed to compile the PDF")
    end
  end

  def crossref_from_markdown(paper_issue=nil, paper_volume=nil, paper_year=nil, paper_month=nil, paper_day=nil)
    cross_ref_template_path = "#{Whedon.resources}/crossref.template"
    bibtex = Bibtex.new(paper.bibtex_path)

    # Pass the citations that are actually in the paper to the CrossRef
    # citations generator.

    citations_in_paper = File.read(paper.paper_path).scan(/@[\w|-]+/)
    citations = bibtex.generate_citations(citations_in_paper)
    authors = paper.crossref_authors
    # TODO fix this when we update the DOI URLs
    # crossref_doi = archive_doi.gsub("http://dx.doi.org/", '')

    paper_day ||= Time.now.strftime('%d')
    paper_month ||= Time.now.strftime('%m')
    paper_year ||= Time.now.strftime('%Y')
    paper_issue ||= @current_issue
    paper_volume ||= @current_volume

    `cd #{paper.directory} && pandoc \
    -V timestamp=#{Time.now.strftime('%Y%m%d%H%M%S')} \
    -V doi_batch_id=#{generate_doi_batch_id} \
    -V formatted_doi=#{paper.formatted_doi} \
    -V archive_doi=#{archive_doi} \
    -V review_issue_url=#{paper.review_issue_url} \
    -V paper_url=#{paper.pdf_url} \
    -V joss_resource_url=#{paper.joss_resource_url} \
    -V journal_alias=#{ENV['JOURNAL_ALIAS']} \
    -V journal_abbrev_title=#{ENV['JOURNAL_ALIAS'].upcase} \
    -V journal_url=#{ENV['JOURNAL_URL']} \
    -V journal_name='#{ENV['JOURNAL_NAME']}' \
    -V journal_issn=#{ENV['JOURNAL_ISSN']} \
    -V citations='#{citations}' \
    -V authors='#{authors}' \
    -V month=#{paper_month} \
    -V day=#{paper_day} \
    -V year=#{paper_year} \
    -V issue=#{paper_issue} \
    -V volume=#{paper_volume} \
    -V page=#{paper.review_issue_id} \
    -V title='#{paper.plain_title}' \
    -f markdown #{File.basename(paper.paper_path)} -o #{paper.filename_doi}.crossref.xml \
    --template #{cross_ref_template_path}`

    if File.exists?("#{paper.directory}/#{paper.filename_doi}.crossref.xml")
      "#{paper.directory}/#{paper.filename_doi}.crossref.xml"
    else
      abort("Looks like we failed to compile the Crossref XML")
    end
  end
end
