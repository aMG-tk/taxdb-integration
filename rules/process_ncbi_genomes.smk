rule get_genomes_ncbi:
	output: 
		links = config["rdir"] + "/{library_name}/assembly_url_genomic.txt",
		summary = config["rdir"] + "/{library_name}/assembly_summary_combined.txt"
	params:
		library_dir = config["rdir"],
		library_name = "{library_name}",
		assembly_level = lambda wildcards: config["assembly_level"][wildcards.library_name],
		script = config["wdir"] + "/scripts/prepare_files_ncbi.R",
		ncbi_server = config["ncbi_server"]
	conda:
                config["wdir"] + "/envs/r.yaml"
	log:
		config["rdir"] + "/logs/get_genomes_ncbi_{library_name}.log"
	shell:
		"""
		wget -O "{params.library_dir}/{params.library_name}/assembly_summary_refseq.txt" "{params.ncbi_server}/genomes/refseq/{params.library_name}/assembly_summary.txt" &>> {log}
		wget -O "{params.library_dir}/{params.library_name}/assembly_summary_genbank.txt" "{params.ncbi_server}/genomes/genbank/{params.library_name}/assembly_summary.txt" &>> {log}
		{params.script} -r "{params.library_dir}/{params.library_name}/assembly_summary_refseq.txt" -g "{params.library_dir}/{params.library_name}/assembly_summary_genbank.txt" -a "{params.assembly_level}" -o "{output.links}" -s "{output.summary}" &>> {log}
		"""

rule download_genomes_ncbi:
	input:
		url = config["rdir"] + "/{library_name}/assembly_url_genomic.txt"
	output:
		download_complete = config["rdir"] + "/{library_name}/genomes/done"
	params:
		outdir = config["rdir"] + "/{library_name}/genomes"
	threads: config["download_threads"]
	conda:
		config["wdir"] + "/envs/download.yaml"
	log:
                config["rdir"] + "/logs/download_genomes_ncbi_{library_name}.log"
	shell:
		"""
		aria2c -i {input.url} -c -l "{params.outdir}/links.log" --dir {params.outdir} --max-tries=20 --retry-wait=5 --max-connection-per-server=1 --max-concurrent-downloads={threads} &>> {log}
		# We need to verify all files are there
		cat {input.url} | xargs -n 1 basename | sort > "{params.outdir}/tmp1"
		find {params.outdir} -type f -name '*.gz' | xargs -n 1 basename | sort > "{params.outdir}/tmp2"
		if diff "{params.outdir}/tmp1" "{params.outdir}/tmp2" 
		then
		  touch "{params.outdir}/done"
		fi
		rm "{params.outdir}/links.log" "{params.outdir}/tmp1" "{params.outdir}/tmp2"
		"""

rule get_taxdump:
	output:
		nodes = config["rdir"] + "/ncbi_taxdump/nodes.dmp",
		names = config["rdir"] + "/ncbi_taxdump/names.dmp"
	params:
		outdir = config["rdir"]
	conda:
		config["wdir"] + "/envs/download.yaml"
	log:
                config["rdir"] + "/logs/get_taxdump.log"
	shell:
		"""
		aria2c --max-tries=20 --retry-wait=5 --dir {params.outdir} http://ftp.ncbi.nlm.nih.gov/pub/taxonomy/new_taxdump/new_taxdump.tar.gz &>> {log}
		mkdir -p "{params.outdir}/ncbi_taxdump/"
		tar -xzvf "{params.outdir}/new_taxdump.tar.gz" --directory "{params.outdir}/ncbi_taxdump/" &>> {log}
		rm "{params.outdir}/new_taxdump.tar.gz"
		"""

rule get_taxpath:
	input:
		nodes = config["rdir"] + "/ncbi_taxdump/nodes.dmp",
		names = config["rdir"] + "/ncbi_taxdump/names.dmp",
		genomes = config["rdir"] + "/{library_name}/assembly_summary_combined.txt"
	output:
		taxonomy = config["rdir"] + "/{library_name}/assembly_taxonomy.txt"
	params:
		outdir = config["rdir"],
		script = config["wdir"] + "/scripts/get_taxpath.R"
	conda:
		config["wdir"] + "/envs/r.yaml"
	log:
                config["rdir"] + "/logs/get_taxpath_{library_name}.log"
	shell:
		"""
		{params.script} -i {input.genomes} -t "{params.outdir}/ncbi_taxdump" -s "{params.outdir}/ncbi_taxdump/accessionTaxa.sql" -o {output.taxonomy} &>> {log}
		"""

rule derep_ncbi:
	input:
		download_complete = config["rdir"] + "/{library_name}/genomes/done",
		taxonomy = config["rdir"] + "/{library_name}/assembly_taxonomy.txt"
	output:
		derep_taxonomy = config["rdir"] + "/{library_name}/derep_assembly_taxonomy.txt"
	params:
		dir = config["rdir"] + "/{library_name}",
		indir = config["rdir"] + "/{library_name}/genomes",
		outdir = config["rdir"] + "/{library_name}/derep_genomes",
		derep_wrapper = config["wdir"] + "/scripts/dereplicate_ncbi_wrapper.sh",
		derep_lineage = lambda wildcards: config["derep_lineage"][wildcards.library_name],
		derep_taxlevel_main = lambda wildcards: config["derep_taxlevel_ncbi_main"][wildcards.library_name],
		derep_taxlevel_sub = lambda wildcards: config["derep_taxlevel_ncbi_sub"][wildcards.library_name],
		derep_threshold_main = lambda wildcards: config["derep_threshold_ncbi_main"][wildcards.library_name],
		derep_threshold_sub = lambda wildcards: config["derep_threshold_ncbi_sub"][wildcards.library_name],
		derep_script = config["derep_script"]
	threads: config["derep_threads"]
	conda:
		config["wdir"] + "/envs/derep.yaml"
	log:
		config["rdir"] + "/logs/derep_ncbi_{library_name}.log"
	shell:
		"""
		{params.derep_wrapper} "{params.derep_lineage}" {params.derep_taxlevel_main} {params.derep_taxlevel_sub} {params.derep_threshold_main} {params.derep_threshold_sub} {params.derep_script} {input.taxonomy} {params.dir} {threads} &>> {log}
		# only select dereplicated genomes from taxonomy table for further processing
		find {params.outdir} -type f -name '*.gz' | xargs -n1 basename | sed 's/\\([0-9]\\)_.*/\\1/' | grep -F -f - {input.taxonomy} > {output.derep_taxonomy}
		# delete non-dereplicated genomes
		find {params.indir} -type f -name '*.gz' | xargs -n 1 -P {threads} rm
		"""

rule collect_ncbi_genomes:
	input:
		derep_taxonomy = config["rdir"] + "/{library_name}/derep_assembly_taxonomy.txt"
	output:
		tax = config["rdir"] + "/tax_combined/{library_name}_derep_taxonomy.txt"
	params:
		indir = config["rdir"] + "/{library_name}/derep_genomes",
		outdir = config["rdir"] + "/derep_combined/"
	shell:
		"""
		mkdir -p {params.outdir}
		find {params.indir} -type f -name '*.gz' | xargs -n 1 mv -t {params.outdir}
		cp {input.derep_taxonomy} {output.tax}
		"""

rule fix_ncbi_taxpath:
	input:
		ncbi = expand(config["rdir"] + "/tax_combined/{library_name}_derep_taxonomy.txt", library_name = LIBRARY_NAME),
		gtdb = config["rdir"] + "/tax_combined/gtdb_derep_taxonomy.txt"
	output:
		ncbi_tax = config["rdir"] + "/tax_combined/ncbi_derep_taxonomy.txt"
	params:
		outdir = config["rdir"] + "/tax_combined",
		script = config["wdir"] + "/scripts/fix_ncbi_taxpath.R"
	conda:
		config["wdir"] + "/envs/r.yaml"
	log:
		config["rdir"] + "/logs/fix_ncbi_taxpath.log"
	shell:
		"""
		cat {input.ncbi} > "{params.outdir}/tmp"
		{params.script} -i "{params.outdir}/tmp" -g {input.gtdb} -o {output.ncbi_tax} &>> {log}
		rm "{params.outdir}/tmp"
		"""

