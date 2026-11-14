"""Generates a SYNTHETIC local copy of the page structure used by books.toscrape.com.
It exists only so the R pipeline can be tested offline. It is NOT real scraped data.
Deliberate defects: '(Â£)' encoding glitch, truncated display titles, stray whitespace,
missing descriptions, one duplicate record, inconsistent category casing."""
import random, html, os
random.seed(7)
out = os.path.join(os.path.dirname(__file__), "pages"); os.makedirs(out, exist_ok=True)
cats = ["Travel", "Poetry", "Mystery", "Business", "Science", "History", "Fiction"]
words = "Silent River Garden Midnight Atlas Harvest Ember Tide Lantern Orchard Compass Winter Harbour Mirror Summit Whisper".split()
rating_words = ["One","Two","Three","Four","Five"]
books = []
for i in range(40):
    t = f"The {random.choice(words)} of {random.choice(words)} {random.choice(['Road','Years','Code','Light','Secrets'])}"
    books.append(dict(id=i, title=t, price=round(random.uniform(10,60),2), rating=random.choice(rating_words),
                      cat=random.choice(cats), stock=random.randint(1,22),
                      desc=None if random.random()<0.2 else " ".join(random.choices(words+["and","the","story","about","a","of","journey"], k=random.randint(25,120)))+"."))
books[39] = dict(books[3], id=39)          # duplicate record
books[11]["cat"] = books[11]["cat"].upper() # inconsistent casing
def pod(b, n):
    shown = b["title"] if len(b["title"])<=24 else b["title"][:21]+"..."
    return f'''<li class="col-xs-6"><article class="product_pod"><div class="image_container"><a href="book_{b['id']}.html"><img src="x.jpg"></a></div>
<p class="star-rating {b['rating']}"><i class="icon-star"></i></p><h3><a href="book_{b['id']}.html" title="{html.escape(b['title'])}">{html.escape(shown)}</a></h3>
<div class="product_price"><p class="price_color">Â£{b['price']:.2f}</p><p class="instock availability"><i class="icon-ok"></i>
    In stock
</p></div></article></li>'''
for p in (1,2):
    chunk = books[(p-1)*20:p*20]
    open(f"{out}/page-{p}.html","w",encoding="utf-8").write("<html><body><ol class='row'>"+"\n".join(pod(b,p) for b in chunk)+"</ol></body></html>")
for b in books:
    d = f"<div id='product_description' class='sub-header'><h2>Product Description</h2></div><p>{b['desc']}</p>" if b["desc"] else ""
    tab = "".join(f"<tr><th>{k}</th><td>{v}</td></tr>" for k,v in [("UPC",f"upc{b['id'] if b['id']!=39 else 3:04d}"),("Product Type","Books"),
        ("Price (excl. tax)",f"Â£{b['price']:.2f}"),("Price (incl. tax)",f"Â£{b['price']:.2f}"),("Tax","Â£0.00"),("Availability",f"In stock ({b['stock']} available)"),("Number of reviews","0")])
    open(f"{out}/book_{b['id']}.html","w",encoding="utf-8").write(f"<html><body><ul class='breadcrumb'><li><a>Home</a></li><li><a>Books</a></li><li><a>{b['cat']}</a></li><li class='active'>{html.escape(b['title'])}</li></ul>{d}<table class='table table-striped'>{tab}</table></body></html>")
print("fixture pages:", len(os.listdir(out)))
