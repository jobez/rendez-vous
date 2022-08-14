(ns jhnn
  (:require
   [reagent.core :as r]
   [reagent.dom :as rdom]
   [react :as react]
   [goog.crypt :as crypt]
   [goog.crypt.Pkcs7]
   [goog.crypt.Md5]
   [clojure.string :as str]
   [shadow.resource :as rc]
   ["./helpers" :as helpers]
   ["bignumber.js" :as bn]
   ["starknet/utils/number" :refer [toBN toHex toFelt]]
   ["starknet/utils/hash" :refer [pedersen  computeHashOnElements]]
   ["starknet/utils/shortString" :refer [encodeShortString decodeShortString]]
   ["@starknet-react/core" :refer
    [StarknetProvider
     getInstalledInjectedConnectors
     useConnectors
     useContract
     useStarknetInvoke
     useStarknetCall
     useStarknet]])
  (:import [goog.crypt Sha256 Hmac Aes Cbc Md5]))

(declare use-cipher str->encoded-short-str)

(defonce prompt-abi (rc/inline "abis/prompt.json"))

(defonce prompt-addr "0x04388ecf27de76fb51b59e494982c27f9db12809c0d55c4bcea632c7bdb6c354")

(defonce counter-abi (rc/inline "counter.json"))

(defonce counter-addr "0x036486801b8f42e950824cba55b2df8cccb0af2497992f807a7e1d9abd2c6ba1")

(defonce timer (r/atom (js/Date.)))

(defonce time-color (r/atom "#f34"))

(defonce time-updater (js/setInterval
                       #(reset! timer (js/Date.)) 1000))

(defn greeting [message]
  [:h1 message])

(defn clock []
  (let [time-str (-> @timer .toTimeString (str/split " ") first)]
    [:div.example-clock
     {:style {:color @time-color}}
     time-str]))

(defn color-input []
  [:div.color-input
   "Time color: "
   [:input {:type "text"
            :value @time-color
            :on-change #(reset! time-color (-> % .-target .-value))}]])

(defn connect []
  (let [connectors-js (->> (useConnectors)
                           )
        connect (aget connectors-js "connect")
        connectors (aget connectors-js "connectors")]

    [:<>
     (for [connector connectors]
       (do
        [:button
         {:key (.-id connector)
          :on-click #(connect connector)}
         (str "Connect " (.name connector))]))]))

(defn greeter []
  (let [starknet-js (useStarknet)
        account (some-> starknet-js
                        (aget "account")
                        )]
    (when account
      [:h1  (str "gm " account)])))

(defn use-counter []
  (useContract #js {:abi (aget (js/JSON.parse counter-abi) "abi")
                    :address counter-addr}))

(defn use-prompt []
  (useContract #js {:abi (js/JSON.parse prompt-abi) 
                    :address prompt-addr}))

(defn prompt-contract []
  (let [contract-js (use-prompt)

        contract (some-> contract-js
                         (aget "contract"))
        starknet-js (useStarknet)
        [text set-text] (react/useState "")
        account (some-> starknet-js
                        (aget "account")
                        )
        [cypher-box error] (use-cipher contract-js)
        cypher (some->
                cypher-box
                (aget  "1"))
        invoke-seq-of-short-str-js (useStarknetInvoke #js {:contract contract :method "write_the_seq_of_short_str"})
        [reset error invoke-seq-of-short-str data loading]
        (mapv #(some->  invoke-seq-of-short-str-js
                       (aget %1))
              ["reset" "error" "invoke" "data" "loading"])
        invoke-set-cypher-js (useStarknetInvoke #js {:contract contract :method "set_cypher"})
        [reset2 error2 invoke-set-cypher data2 loading2] (mapv #(some->  invoke-set-cypher-js
                       (aget %1))
              ["reset" "error" "invoke" "data" "loading"])
        ]
    (when account
      (println cypher-box)
      (if (or data error)
        [:div
         [:b (or data error)]
         [:button {:on-click #((reset))} "reset"]]
        (if loading
          [:i loading]
          [:div
           [:button {:on-click #(invoke-set-cypher #js {:args #js []})}
            "Set cypher"]
           [:textarea {:name "texty"
                       :value text
                       :on-change    #(set-text (.. % -target -value))
                       :on-key-press (fn [e]
                                       (when (= (.-charCode e) 13)
                                         (.preventDefault e)
                                         (set-text "")))
                       :cols "40"
                       :rows "5"}]
           [:button {:on-click (fn [e]
                                 (let [partitioned-strings (re-seq #".{1,31}" text)
                                       encoded-strings (->> partitioned-strings
                                                            (map #(str->encoded-short-str %1 cypher))
                                                            (clj->js ))]
                                  (-> (invoke-seq-of-short-str #js {:args #js [ encoded-strings
                                                              ]})
                                      ))
                                 )}
            (str "write_the_seq_of_short_str" data)]])))))

(defn maybe-deprefix [supposed-hex]
  (if (clojure.string/starts-with? "0x" supposed-hex)
    (clojure.string/replace-first supposed-hex
                                  #"0x"
                                  "")
    supposed-hex))

(defn maybe-prefix [supposed-hex]
  (if (not (clojure.string/starts-with? supposed-hex "0x"))
    (str "0x" supposed-hex)
    supposed-hex))

(comment
 (tests
  (maybe-prefix "616d6572696361206973206772656174") := "0x616d6572696361206973206772656174"
  (maybe-prefix "0x616d6572696361206973206772656174") := "0x616d6572696361206973206772656174"))

(defn str->encoded-short-str [string cypher]
  (let [hex (reduce
             (fn [acc idx]
               (str acc (-> (.charCodeAt string idx)
                            (.toString 16))))
             ""
             (range (.-length string)))
        added-cypher (+ (js/BigInt (str "0x" hex)) (js/BigInt cypher))]
    (str "0x" (.toString added-cypher 16))))


(defn decipher [input cypher]
  (when cypher
   (- (js/BigInt (maybe-prefix input)) (js/BigInt cypher))))

(defn encoded-short-str->str [%string]
  (let [string (maybe-deprefix %string)
        by-two (re-seq #".{2}" string)]
    (reduce #(->> (js/parseInt %2 16)
                  (js/String.fromCharCode )
                  (str %1 ))
            ""
          by-two)
    ))

(comment
  (tests
   (encoded-short-str->str (.toString (decipher (str->encoded-short-str "america is great" 1069894870859055890) 1069894870859055890) 16)) := "america is great"

   ))

(defn counter-contract []
  (let [contract-js (use-counter)

        contract (some-> contract-js
                         (aget "contract"))
        starknet-js (useStarknet)
        account (some-> starknet-js
                        (aget "account")
                        )
        invoke-js (useStarknetInvoke #js {:contract contract :method "incrementCounter"})
        reset (some-> invoke-js
                      (aget "reset"))
        error (some-> invoke-js
                      (aget "error"))
        invoke (some-> invoke-js
                       (aget "invoke"))
        data (some-> invoke-js
                     (aget "data"))
        loading (some-> invoke-js
                        (aget "loading"))]
   (r/as-element
     (when account
       (if (or data error)
         [:div
          [:b (or data error)]
          [:button {:on-click #((reset))} "reset"]]
         (if loading
           [:i loading]
           [:button {:on-click (fn [e]
                                 (-> (invoke #js {:args #js ["0x1" ]})
                                     (.then (fn [e]
                                              (js/console.log e)))
                                     (.catch (fn [e]
                                               (js/console.log e))))
                                 )}
            (str "Increment by one" data)]))))))

(defn view-counter []
  (let [contract-js (use-counter)

        contract (some-> contract-js
                         (aget "contract"))
        contract-call-js (useStarknetCall #js {:contract contract
                                               :method "counter"
                                               :args #js []} )

        starknet-js (useStarknet)
        account (some-> starknet-js
                        (aget "account")
                        )
        [counter error] (mapv #(aget contract-call-js %)
                              ["data" "error"])]

    [:div (some-> counter
                  (toBN )
                  (.toString ))]
    ))

(defn use-cipher [contract-js]
  (let [contract (some-> contract-js
                         (aget "contract"))
        contract-call-cypher-js (useStarknetCall #js {:contract contract
                                               :method "get_cypher"
                                                      :args #js []} )
        ]
    (mapv #(aget contract-call-cypher-js %)
                              ["data" "error"])))

(defn view-prompt []
  (let [contract-js (use-prompt)

        contract (some-> contract-js
                         (aget "contract"))
        [cypher-box error] (use-cipher contract-js)
        cypher (some->
                cypher-box
                (aget  "1"))
        prompt-call-js (useStarknetCall #js {:contract contract
                                               :method "read_the_seq_of_short_str"
                                               :args #js []} )
        starknet-js (useStarknet)
        account (some-> starknet-js
                        (aget "account")
                        )
        [prompt-seq error] (mapv #(aget prompt-call-js %)
                              ["data" "error"])]

    [:div
     [:div (str
            "Cipher "
            (some-> cypher
                       .toString))]
     [:div (some-> prompt-seq
                   (aget "0")
                   array-seq
                   (->>
                    (map #(toHex %))
                    (map #(some-> (decipher % cypher)
                              (.toString 16)
                              (encoded-short-str->str)))
                    (apply str))
                   )]]
     ))

(defn simple-example []
  (let [injected-connectors (getInstalledInjectedConnectors)]
   [(r/adapt-react-class StarknetProvider)
    {:connectors injected-connectors}
    [:f> greeter]
    [:f> connect]
    [:f> prompt-contract]
    [:f> view-prompt]
    ;; [clock]
    ;; [color-input]
    ]))

(defn  init []
  (rdom/render [simple-example] (js/document.getElementById "app")))
