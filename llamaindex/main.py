import os
import os.path
import logging
import sys
import json
from flask import Flask, request
import boto3
from llama_index import SimpleDirectoryReader
from llama_index import GPTListIndex, GPTVectorStoreIndex
from llama_index import StorageContext
from llama_index import LangchainEmbedding
from llama_index.storage.docstore import SimpleDocumentStore
from llama_index.storage.index_store import SimpleIndexStore
from llama_index.vector_stores import SimpleVectorStore
from llama_index import ServiceContext
from llama_index.node_parser import SimpleNodeParser
from llama_index.embeddings.openai import OpenAIEmbedding
from llama_index import LLMPredictor
from llama_index.indices.prompt_helper import PromptHelper
from llama_index.logger.base import LlamaLogger
from llama_index.callbacks.base import CallbackManager
from llama_index.indices.list.base import ListRetrieverMode
from llama_index.indices.response import ResponseMode
from llama_index.prompts.prompts import (
    QuestionAnswerPrompt,
    RefinePrompt,
    SimpleInputPrompt,
)
from llama_index.prompts.default_prompts import (
    DEFAULT_TEXT_QA_PROMPT_TMPL,
    DEFAULT_SIMPLE_INPUT_TMPL,
    DEFAULT_REFINE_PROMPT_TMPL,
)
from langchain.chat_models import ChatOpenAI
from langchain.embeddings import OpenAIEmbeddings

############ ロギング ###########
logging.basicConfig(stream=sys.stdout, level=logging.INFO)
logging.getLogger().addHandler(logging.StreamHandler(stream=sys.stdout))

############ AWSのSSMから環境変数を取ってくる ############
ssm = boto3.client("ssm", region_name="ap-northeast-1")
parameter = ssm.get_parameter(Name="/my-gpt/server/dotenv", WithDecryption=True)
parameter_lines = parameter["Parameter"]["Value"].split("\n")
for line in parameter_lines:
    key, value = line.split("=")
    os.environ[key] = value

############ StorageContextの初期化 ############
if os.path.exists("./cache"):
    print("create storage context from cache")
    # persist_dirを利用したいため、明示的にstoreを指定することはしない
    storage_context = StorageContext.from_defaults(persist_dir="./cache")
else:
    storage_context = StorageContext.from_defaults(
        docstore=SimpleDocumentStore(),  # テキストデータが保管されている。InMemory
        vector_store=SimpleVectorStore(),  # ベクトルデータが保管されている。InMemory
        index_store=SimpleIndexStore(),  # インデックスに関する情報が保管されている。InMemory
    )

############ ServiceContextの初期化 ############
# NodeParserの設定
# NodeParserは、テキストをチャンクに分割してノードを作成する部分を担っている
node_parser = SimpleNodeParser()
# Embeddingsの設定
# テキストを埋め込みベクトルに変換する部分を担っている
embedding = OpenAIEmbeddings(model="text-embedding-ada-002")
llama_embed = LangchainEmbedding(embedding, embed_batch_size=1)
# LLMPredictorの設定
# テキスト応答（Completion）を得るための言語モデルの部分を担っている
llm_predictor = LLMPredictor(ChatOpenAI())
# PromptHelperの設定
# PromptHelperは、トークン数制限を念頭において、テキストを分割するなどの部分を担っている
prompt_helper = PromptHelper(
    max_input_size=4096,  # LLMに入力するトークンの最大サイズ
    num_output=256,  # LLMから出力するトークンの最大サイズ
    max_chunk_overlap=20,  # LLMに入力する際のチャンクのオーバーラップの最大サイズ
)
# コールバックの設定
# LlamaIndexの様々な処理のstart, endでコールバックを設定することができる
# CallbackManagerにCallbackHandlerを設定することで、各CallbackHandlerのon_event_start, on_event_endが発火する
callback_manager = CallbackManager([])
# Loggerの設定
# 主にLLMへのクエリのログを取得するのに使用される
logger = LlamaLogger()

service_context = ServiceContext.from_defaults(
    node_parser=node_parser,
    embed_model=llama_embed,
    llm_predictor=llm_predictor,
    prompt_helper=prompt_helper,
    llama_logger=logger,
    callback_manager=callback_manager,
)

############ Indexの初期化 ############
documents = SimpleDirectoryReader(input_dir="./data").load_data()
list_index = GPTVectorStoreIndex.from_documents(
    documents, storage_context=storage_context, service_context=service_context
)
# 生成したIndexを保存する
list_index.storage_context.persist("./cache")

############ QueryEngineの初期化 ############
# GPTVectorStoreIndexを利用しているのでRetrieverModeとしては「埋め込みベクトルを使って抽出」
# retriever_mode=ListRetrieverMode.DEFAULT

# QuestionAnswerPromptの定義（デフォルトが英語なので日本語で再定義）
MY_TEXT_QA_PROMPT_TMPL = (
    "コンテキスト情報は以下のとおりです。 \n"
    "---------------------\n"
    "{context_str}"
    "\n---------------------\n"
    "予備知識ではなくコンテキスト情報を考慮して、質問に答えてください。:{query_str}\n"
)
# RefinePromptの定義（デフォルトが英語なので日本語で再定義）
MY_REFINE_PROMPT_TMPL = (
    "元の質問は次のとおりです: {query_str}\n"
    "既存の回答を提供しました: {existing_answer}\n"
    "以下の追加のコンテキストを使用して、既存の回答を (必要な場合のみ) 改良する機会があります。\n"
    "------------\n"
    "{context_msg}\n"
    "------------\n"
    "新しいコンテキストを考慮して、元の答えをより良いものに改良してください。"
    "コンテキストが役に立たない場合は、元の回答を返してください。"
)

query_engine = list_index.as_query_engine(
    node_postprocessors=[],  # Node抽出後の後処理
    optimizer=None,  # 各Nodeのテキストに適用したい後処理
    response_mode=ResponseMode.COMPACT,  # レスポンス合成のモード
    # 以下は各種Promptのテンプレート定義
    text_qa_template=QuestionAnswerPrompt(MY_TEXT_QA_PROMPT_TMPL),
    refine_template=RefinePrompt(MY_REFINE_PROMPT_TMPL),
    simple_template=SimpleInputPrompt(DEFAULT_SIMPLE_INPUT_TMPL),
)

############ Flaskの初期化 ############
app = Flask(__name__)
app.config["JSON_AS_ASCII"] = False


@app.route("/", methods=["GET"])
def healthcheck():
    return json.dumps("ok", ensure_ascii=False), 200


@app.route("/chat/completions", methods=["POST"])
def chat_completions():
    auth_header = request.headers.get("Authorization")
    if auth_header != f"Bearer {os.getenv('API_KEY')}":
        return json.dumps({"error": "認証エラーです"}, ensure_ascii=False), 401

    data = request.get_json()
    prompt = data.get("prompt")

    if prompt is not None:
        print(f"Received prompt: {prompt}")
        response = query_engine.query(prompt)
        print(f"Completion: {response.response}")
        print(response.get_formatted_sources(length=4096))
        response_body = {"content": response.response}
        return json.dumps(response_body, ensure_ascii=False), 200
    else:
        return json.dumps({"error": "promptは必須です"}, ensure_ascii=False), 400


############ Flaskサーバーの起動 ############
if __name__ == "__main__":
    print(f"Starting server... port={os.getenv('PORT', '80')}")
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "80")), debug=True)
