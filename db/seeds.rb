require 'active_record'
require 'csv'

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#

#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

input_file = "db/lexique_dict_full.txt"
csv_file = "db/parsed_lexique.csv"

ApiSweeper.disabled = true

def sanitise(value)
    value.strip.gsub("'", "''").gsub(160.chr("UTF-8"), "")  # Remove None-Ascii UTF-8 blank space, will not be removed by strip()
end

def extract_all_translations(sentences)
    splits = sentences.split(".")
    if splits.length != 3 # exceptional cases - just treat everything  as "translation"
        meaning =  sentences.lstrip.strip
        return meaning, nil, nil
    end
    meaning = splits[0].lstrip.strip
    example = nil
    example_translation = nil
    if splits.length() >= 2
        example = splits[1].lstrip.strip
    end
    if splits.length() >= 3
        example_translation = splits[2].lstrip.strip
    end
    return meaning, example, example_translation
end

def consider_to_publish(meaning, example, example_translation, category_values, added_categories)
    if category_values.length() != 1
        return false, added_categories
    end
    category_value = category_values[0]
    if added_categories.length() <= 10
        if meaning && example && example_translation
            if not added_categories.include?(category_value)
                added_categories.add(category_value)
                return true, added_categories
            end
        end
    end
    return false, added_categories
end

def extract_categories(categories_string)
    categories_string.split(",").each{ |x| x.strip!}
end

def clean_up_category(line)

    if not (line.include? "Category")
        line = line.gsub("\n", "Category: EmptyCategory\n")
    end

    if (line.include? "elements : c")
        line = line.gsub("elements : c", "elements")
    end
    line
end

def save_entry_to_db(entry, added_categories)
        # Example of an entry:
        # Bambarrwarn  	[Bam-barr-warn] nominal. Goosehole. billabong southwest of the Fitzroy Crossing Lodge. Bambarrwarn gamba goorroorla. Goosehole is a billabong.

    return false, added_categories if (!entry)
    word = sanitise(entry[0])
    pronunciation = sanitise(entry[1])
    word_type = sanitise(entry[2])
    meaning, example, example_translation = extract_all_translations(sanitise(entry[3]))
    category_values_string = extract_categories(entry[4])

    # category_values = category_values_string.each {|category| Category.find_or_create_by(name: category)}
    categories = []
    for category_string in category_values_string
        if category_string != "EmptyCategory"
            category = Category.find_or_create_by(name: category_string)
            categories.append(category)
        end
    end
    is_published, added_categories = consider_to_publish(meaning, example, example_translation, category_values_string, added_categories)
    entry = Entry.create(
        entry_word: word,
        word_type: word_type,
        meaning: meaning,
        example: example,
        example_translation: example_translation,
        categories: categories,
        pronunciation: pronunciation,
        published?: is_published
    )
    print("\n Parsed SUCCESSFULLY entry:", word, "ƒ\n")
    # print("\n\n Parsed SUCCESSFULLY entry:", word, "\nword type:", word_type, "\n meaning: ", meaning, "\n example: ", example, "\nCategory:", category_value, "\n")
    return true, added_categories
end

File.delete(csv_file) if File.exist?(csv_file)
line_num = 0
success_count = 0
shared_first_part = ""
added_categories = Set[]
Category.find_or_create_by(name: 'Common Phrases')

CSV.open(csv_file, "w") do |csv|
    File.open(input_file,:encoding => 'utf-8').each do |line|
        # if line_num > 500
        #     break
        # end

        if (line.include? "1 •")
            shared_first_part = line[0, line.index("1 •")] # store first part to reuse for #2 meaning
            line = line.gsub("1 •", "")  # continue process meaning #1 as normal
            print("\n---------------\nProcessing 1st part >>>", line, "\n\n")
        end

        if  (line.include? "2 •")
            line = line.gsub("2 •", "")
            line = shared_first_part + line
            print("\n---------------\nProcessing 2nd part >>>", line, "\n\n")
        end

        line = clean_up_category(line)

        if not (line.index(/^[^.]+\[/))  # first pronunciation [ ] - no dots preceding
            line = line.insert(line.index(/\s/) + 1, " [] ")
        end

        result = line.scan(/(\S+)\W+\[(.*)\]\W+([^.]+)\.(.+)Category:\W+([^.]+)/)
        actual_value = result.first()
        if actual_value
            status, added_categories = save_entry_to_db(actual_value, added_categories)
            success_count += 1 if status
        else
            # print("\nSkip line!: ", line, " --- Actual value: ", actual_value, "\n")
            csv << [line]
        end
        line_num += 1
    end

    print("\n\nTotal success: ", success_count)
end
